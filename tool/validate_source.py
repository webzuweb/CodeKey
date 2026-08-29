#!/usr/bin/env python3
"""Static validation for the portable CodeKey Flutter source archive."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Validator:
    def __init__(self) -> None:
        self.results: list[dict[str, object]] = []

    def check(self, name: str, condition: bool, detail: object | None = None) -> None:
        self.results.append(
            {
                "name": name,
                "result": "PASS" if condition else "FAIL",
                "detail": detail,
            }
        )
        if not condition:
            print(f"FAIL: {name}: {detail}")

    @property
    def passed(self) -> bool:
        return all(item["result"] == "PASS" for item in self.results)


def strip_dart(text: str) -> str:
    """Replace comments and string contents while preserving line positions."""
    output: list[str] = []
    index = 0
    state = "code"
    quote = ""
    triple = False
    raw = False
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""
        if state == "code":
            if char == "/" and nxt == "/":
                output.extend("  ")
                index += 2
                state = "line_comment"
                continue
            if char == "/" and nxt == "*":
                output.extend("  ")
                index += 2
                state = "block_comment"
                continue
            if char == "r" and nxt in "'\"":
                raw = True
                output.append(" ")
                index += 1
                char = text[index]
            if char in "'\"":
                quote = char
                triple = text[index : index + 3] == char * 3
                output.append(" ")
                index += 1
                if triple:
                    output.extend("  ")
                    index += 2
                state = "string"
                continue
            output.append(char)
            index += 1
            continue

        if state == "line_comment":
            output.append("\n" if char == "\n" else " ")
            index += 1
            if char == "\n":
                state = "code"
            continue

        if state == "block_comment":
            if char == "*" and nxt == "/":
                output.extend("  ")
                index += 2
                state = "code"
            else:
                output.append("\n" if char == "\n" else " ")
                index += 1
            continue

        if state == "string":
            if triple and text[index : index + 3] == quote * 3:
                output.extend("   ")
                index += 3
                state = "code"
                raw = False
                continue
            if not triple and char == quote:
                output.append(" ")
                index += 1
                state = "code"
                raw = False
                continue
            if not raw and char == "\\":
                output.append(" ")
                index += 1
                if index < len(text):
                    output.append("\n" if text[index] == "\n" else " ")
                    index += 1
                continue
            output.append("\n" if char == "\n" else " ")
            index += 1
    return "".join(output)


def delimiters_balanced(path: Path) -> tuple[bool, str]:
    text = strip_dart(path.read_text(encoding="utf-8"))
    closing = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    for index, char in enumerate(text):
        if char in "([{":
            stack.append((char, index))
        elif char in closing:
            if not stack or stack[-1][0] != closing[char]:
                return False, f"unexpected {char} at offset {index}"
            stack.pop()
    if stack:
        return False, f"unclosed {stack[-1][0]} at offset {stack[-1][1]}"
    return True, ""


def localization_keys(text: str, language: str) -> list[str]:
    marker = f"    '{language}': {{"
    start = text.index(marker) + len(marker)
    keys: list[str] = []
    for line in text[start:].splitlines():
        if line.startswith("    },"):
            break
        match = re.match(r"\s+'([^']+)':", line)
        if match:
            keys.append(match.group(1))
    return keys


def test_bootstrap_patches(validator: Validator) -> None:
    script = ROOT / "tool/bootstrap_platforms.py"
    spec = importlib.util.spec_from_file_location("codekey_bootstrap", script)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    with tempfile.TemporaryDirectory(prefix="codekey-bootstrap-test-") as temp:
        fake = Path(temp)
        (fake / "android/app/src/main").mkdir(parents=True)
        (fake / "android/app").mkdir(parents=True, exist_ok=True)
        (fake / "ios/Runner").mkdir(parents=True)
        (fake / "ios/Runner.xcodeproj").mkdir(parents=True)
        (fake / "ios/Flutter").mkdir(parents=True)

        (fake / "android/app/src/main/AndroidManifest.xml").write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '  <application android:label="codekey_app" android:name="${applicationName}">\n'
            '  </application>\n</manifest>\n',
            encoding="utf-8",
        )
        (fake / "android/app/build.gradle.kts").write_text(
            "plugins { id(\"com.android.application\") }\n"
            "\nandroid {\n"
            "    defaultConfig { minSdk = flutter.minSdkVersion }\n"
            "    buildTypes {\n"
            "        release {\n"
            "            signingConfig = signingConfigs.getByName(\"debug\")\n"
            "        }\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )

        import plistlib

        with (fake / "ios/Runner/Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleName": "CodeKey"}, handle)
        (fake / "ios/Podfile").write_text(
            "platform :ios, '13.0'\n\n"
            "target 'Runner' do\n"
            "  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))\n"
            "end\n\n"
            "post_install do |installer|\n"
            "  installer.pods_project.targets.each do |target|\n"
            "    flutter_additional_ios_build_settings(target)\n"
            "  end\n"
            "end\n",
            encoding="utf-8",
        )
        (fake / "ios/Runner.xcodeproj/project.pbxproj").write_text(
            "IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n",
            encoding="utf-8",
        )
        with (fake / "ios/Flutter/AppFrameworkInfo.plist").open("wb") as handle:
            plistlib.dump({"MinimumOSVersion": "13.0"}, handle)

        original_root = module.ROOT
        module.ROOT = fake
        try:
            module.patch_android()
            module.patch_ios()
        finally:
            module.ROOT = original_root

        manifest = (fake / "android/app/src/main/AndroidManifest.xml").read_text()
        gradle = (fake / "android/app/build.gradle.kts").read_text()
        podfile = (fake / "ios/Podfile").read_text()
        with (fake / "ios/Runner/Info.plist").open("rb") as handle:
            info = plistlib.load(handle)

        validator.check("bootstrap Android BLE permission", "BLUETOOTH_SCAN" in manifest)
        validator.check("bootstrap Android camera permission", "permission.CAMERA" in manifest)
        validator.check("bootstrap Android HTTPS only", 'usesCleartextTraffic="false"' in manifest)
        validator.check("bootstrap Android minSdk 24", "minSdk = 24" in gradle)
        validator.check(
            "bootstrap Android Chinese OCR",
            "text-recognition-chinese:16.0.1" in gradle,
        )
        validator.check("bootstrap Android signing", "keystoreProperties" in gradle)
        validator.check("bootstrap iOS target 15.5", "platform :ios, '15.5'" in podfile)
        validator.check(
            "bootstrap iOS Chinese OCR",
            "GoogleMLKit/TextRecognitionChinese" in podfile,
        )
        validator.check("bootstrap iOS camera macro", "PERMISSION_CAMERA=1" in podfile)
        validator.check("bootstrap iOS Bluetooth macro", "PERMISSION_BLUETOOTH=1" in podfile)
        validator.check("bootstrap iOS camera description", "NSCameraUsageDescription" in info)
        validator.check("bootstrap iOS Bluetooth description", "NSBluetoothAlwaysUsageDescription" in info)
        validator.check("bootstrap iOS photo description", "NSPhotoLibraryUsageDescription" in info)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flutter", action="store_true", help="also run Flutter analyze/tests")
    parser.add_argument(
        "--report",
        default=str(ROOT / "VALIDATION.json"),
        help="JSON report path",
    )
    args = parser.parse_args()

    validator = Validator()
    required = [
        "pubspec.yaml",
        "lib/main.dart",
        "lib/app_logger.dart",
        "lib/app_controller.dart",
        "lib/ble_service.dart",
        "lib/ocr_service.dart",
        "lib/settings_page.dart",
        "lib/home_page.dart",
        "tool/bootstrap_platforms.py",
        "tool/build_android.bat",
        "tool/build_ios.sh",
        "docs/DIAGNOSTICS_RU.md",
    ]
    for relative in required:
        validator.check(f"required file {relative}", (ROOT / relative).exists())

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    validator.check("package version 0.3.1+4", "version: 0.3.1+4" in pubspec)
    validator.check("Android and iOS description", "Android and iOS" in pubspec)
    validator.check("ML Kit dependency", "google_mlkit_text_recognition: 0.15.1" in pubspec)
    validator.check("diagnostic share dependency", "share_plus: ^13.3.0" in pubspec)

    localization = (ROOT / "lib/localization.dart").read_text(encoding="utf-8")
    languages = {lang: localization_keys(localization, lang) for lang in ("ru", "en", "es", "zh")}
    base = set(languages["ru"])
    for language, keys in languages.items():
        validator.check(
            f"localization {language} key parity",
            set(keys) == base and len(keys) == len(set(keys)),
            f"{len(keys)} keys",
        )
    dart_text = "\n".join(path.read_text() for path in (ROOT / "lib").glob("*.dart"))
    direct_calls = set(re.findall(r"\.t\(\s*'([^']+)'", dart_text))
    validator.check(
        "direct localization calls resolved",
        direct_calls.issubset(base),
        sorted(direct_calls - base),
    )

    for path in sorted((ROOT / "lib").glob("*.dart")) + sorted((ROOT / "test").glob("*.dart")):
        ok, detail = delimiters_balanced(path)
        validator.check(f"delimiter balance {path.relative_to(ROOT)}", ok, detail or None)

    controller = (ROOT / "lib/app_controller.dart").read_text()
    home = (ROOT / "lib/home_page.dart").read_text()
    settings = (ROOT / "lib/settings_page.dart").read_text()
    models = (ROOT / "lib/models.dart").read_text()
    llm = (ROOT / "lib/llm_service.dart").read_text()
    logger = (ROOT / "lib/app_logger.dart").read_text()
    bootstrap = (ROOT / "tool/bootstrap_platforms.py").read_text()

    validator.check("immediate screenshot insertion", controller.index("ScreenshotItem(id: id, path: image.path)") < controller.index("unawaited(_persistAndRecognize"))
    validator.check("lost camera data recovery", "retrieveLostData" in controller)
    validator.check("OCR retry", "Future<void> retryOcr" in controller and "retryOcr" in home)
    validator.check("screenshot delete cross", "Icons.close_rounded" in home and "removeScreenshot" in home)
    validator.check("language applies immediately", "updateInterfaceLanguage" in settings and "updateInterfaceLanguage" in controller)
    validator.check("DeepSeek provider", "deepSeek" in models and "_completeDeepSeek" in llm)
    validator.check("DeepSeek endpoint preset", "https://api.deepseek.com" in settings)
    validator.check("DeepSeek strict JSON", "response_format" in llm and "json_object" in llm)
    validator.check("layout cycle from header", "cycleKeyboardLayout" in home and "cycleKeyboardLayout" in controller)
    validator.check("custom layout management", "_addLayout" in settings and "_deleteLayout" in settings)
    validator.check("visible BLE scan state", "controller.scanning" in settings and "_hasScanned" in settings)
    validator.check("USB section gated by connection", "if (controller.deviceStatus.isReady)" in settings)
    validator.check("save returns home", "Navigator.of(context).pop(true)" in settings)
    validator.check("diagnostic logger", "class AppLogger" in logger and "exportDiagnostics" in logger)
    validator.check("diagnostic share sheet", "SharePlus.instance.share" in settings)
    validator.check("log sanitizer", "<redacted>" in logger and "PRIVATE KEY" in logger)
    validator.check("platform generator Android+iOS", '"--platforms=android,ios"' in bootstrap)
    validator.check("iOS ML Kit target", "15.5" in bootstrap and "armv7" in bootstrap)

    # The external API payload must not add local execution metadata.
    for forbidden in (
        "settings.os",
        "settings.editor",
        "activeKeyboardLayout",
        "settings.usbVid",
        "settings.usbPid",
        "bleDeviceId",
    ):
        validator.check(f"LLM payload excludes {forbidden}", forbidden not in llm)

    test_bootstrap_patches(validator)

    # Python scripts must at least parse in the packaging environment.
    scripts = sorted((ROOT / "tool").glob("*.py"))
    py_compile = subprocess.run(
        [shutil.which("python3") or "python3", "-m", "py_compile", *map(str, scripts)],
        capture_output=True,
        text=True,
    )
    validator.check("Python tools compile", py_compile.returncode == 0, py_compile.stderr.strip() or None)

    if args.flutter:
        flutter = shutil.which("flutter")
        validator.check("Flutter SDK available", flutter is not None)
        if flutter:
            for name, command in (
                ("flutter pub get", [flutter, "pub", "get"]),
                ("flutter analyze", [flutter, "analyze"]),
                ("flutter test", [flutter, "test"]),
            ):
                completed = subprocess.run(command, cwd=ROOT)
                validator.check(name, completed.returncode == 0)

    report = {
        "status": "PASS" if validator.passed else "FAIL",
        "checks": len(validator.results),
        "flutterExecuted": bool(args.flutter and shutil.which("flutter")),
        "details": validator.results,
    }
    report_path = Path(args.report)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{report['status']}: {report['checks']} checks; report: {report_path}")
    return 0 if validator.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
