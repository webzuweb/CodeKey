#!/usr/bin/env python3
"""Generate Android and iOS runners for CodeKey and apply native settings.

The archive keeps portable Flutter sources under version control. This script
uses the locally installed Flutter SDK to create runners compatible with that
SDK, then applies CodeKey BLE, camera, ML Kit OCR and signing configuration.
"""

from __future__ import annotations

import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESERVE = [
    "lib",
    "test",
    "tool",
    "docs",
    "assets",
    "pubspec.yaml",
    "analysis_options.yaml",
    "README.md",
    "CHANGELOG.md",
]


def run(*args: str, cwd: Path | None = None) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd or ROOT, check=True)


def patch_android_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    text = path.read_text(encoding="utf-8")
    permissions = """\
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
"""
    if "android.permission.BLUETOOTH_SCAN" not in text:
        text = text.replace("<application", permissions + "\n    <application", 1)
    if "android:usesCleartextTraffic" not in text:
        text = text.replace(
            "<application",
            '<application\n        android:usesCleartextTraffic="false"',
            1,
        )
    text = text.replace('android:label="codekey_app"', 'android:label="CodeKey"')
    path.write_text(text, encoding="utf-8")


def patch_android_min_sdk() -> None:
    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        replacements = (
            [
                ("minSdk = flutter.minSdkVersion", "minSdk = 24"),
                ("minSdk = 21", "minSdk = 24"),
                ("minSdk = 23", "minSdk = 24"),
            ]
            if path.suffix == ".kts"
            else [
                ("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24"),
                ("minSdk flutter.minSdkVersion", "minSdk 24"),
                ("minSdkVersion 21", "minSdkVersion 24"),
                ("minSdkVersion 23", "minSdkVersion 24"),
            ]
        )
        for old, new in replacements:
            if old in text:
                text = text.replace(old, new, 1)
                break
        if text == original and not re.search(r"minSdk(?:Version)?\s*(?:=\s*)?24", text):
            raise RuntimeError(f"Could not set Android minSdk in {path}")
        path.write_text(text, encoding="utf-8")
        return
    raise FileNotFoundError("Generated Android app Gradle file was not found")


def patch_android_dependencies() -> None:
    dependency = "com.google.mlkit:text-recognition-chinese:16.0.1"
    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if dependency not in text:
            if path.suffix == ".kts":
                block = f'\n\ndependencies {{\n    implementation("{dependency}")\n}}\n'
            else:
                block = f"\n\ndependencies {{\n    implementation '{dependency}'\n}}\n"
            path.write_text(text.rstrip() + block, encoding="utf-8")
        return
    raise FileNotFoundError("Generated Android app Gradle file was not found")


def patch_kotlin_signing(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "CodeKey optional release signing" in text:
        return

    if "import java.util.Properties" not in text:
        text = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + text

    marker = "\nandroid {\n"
    properties = """
// CodeKey optional release signing. Copy key.properties.example to
// android/key.properties and provide your private keystore values.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
"""
    if marker not in text:
        raise RuntimeError("android block was not found in build.gradle.kts")
    text = text.replace(marker, properties + marker, 1)

    build_types = "    buildTypes {\n"
    signing = """    // CodeKey optional release signing.
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

"""
    if build_types not in text:
        raise RuntimeError("buildTypes block was not found in build.gradle.kts")
    text = text.replace(build_types, signing + build_types, 1)

    debug_line = '            signingConfig = signingConfigs.getByName("debug")'
    signed_line = (
        '            signingConfig = if (keystorePropertiesFile.exists()) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
    )
    if debug_line in text:
        text = text.replace(debug_line, signed_line, 1)
    else:
        release_marker = "        release {\n"
        if release_marker not in text:
            raise RuntimeError("release build type was not found in build.gradle.kts")
        text = text.replace(release_marker, release_marker + signed_line + "\n", 1)
    path.write_text(text, encoding="utf-8")


def patch_groovy_signing(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "CodeKey optional release signing" in text:
        return

    marker = "\nandroid {\n"
    properties = """
// CodeKey optional release signing. Copy key.properties.example to
// android/key.properties and provide your private keystore values.
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""
    if marker not in text:
        raise RuntimeError("android block was not found in build.gradle")
    text = text.replace(marker, properties + marker, 1)

    build_types = "    buildTypes {\n"
    signing = """    // CodeKey optional release signing.
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            release {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
                storePassword keystoreProperties['storePassword']
            }
        }
    }

"""
    if build_types not in text:
        raise RuntimeError("buildTypes block was not found in build.gradle")
    text = text.replace(build_types, signing + build_types, 1)

    signed_line = (
        "            signingConfig = keystorePropertiesFile.exists() ? "
        "signingConfigs.release : signingConfigs.debug"
    )
    for pattern in (
        "            signingConfig signingConfigs.debug",
        "            signingConfig = signingConfigs.debug",
    ):
        if pattern in text:
            text = text.replace(pattern, signed_line, 1)
            break
    else:
        release_marker = "        release {\n"
        if release_marker not in text:
            raise RuntimeError("release build type was not found in build.gradle")
        text = text.replace(release_marker, release_marker + signed_line + "\n", 1)
    path.write_text(text, encoding="utf-8")


def patch_android_signing() -> None:
    kts = ROOT / "android/app/build.gradle.kts"
    groovy = ROOT / "android/app/build.gradle"
    if kts.exists():
        patch_kotlin_signing(kts)
    elif groovy.exists():
        patch_groovy_signing(groovy)
    else:
        raise FileNotFoundError("Generated Android app Gradle file was not found")

    (ROOT / "android/key.properties.example").write_text(
        "storePassword=CHANGE_ME\n"
        "keyPassword=CHANGE_ME\n"
        "keyAlias=upload\n"
        "storeFile=../upload-keystore.jks\n",
        encoding="utf-8",
    )


def patch_android() -> None:
    patch_android_manifest()
    patch_android_min_sdk()
    patch_android_dependencies()
    patch_android_signing()


def patch_ios_info_plist() -> None:
    info_path = ROOT / "ios/Runner/Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    info["NSCameraUsageDescription"] = (
        "CodeKey photographs a workstation screen and recognizes code locally on this device."
    )
    info["NSPhotoLibraryUsageDescription"] = (
        "CodeKey may read a captured image while restoring an interrupted camera operation."
    )
    info["NSBluetoothAlwaysUsageDescription"] = (
        "CodeKey connects to the ESP32-S3 keyboard bridge over Bluetooth."
    )
    info["NSBluetoothPeripheralUsageDescription"] = info[
        "NSBluetoothAlwaysUsageDescription"
    ]
    info["CFBundleAllowMixedLocalizations"] = True
    info["CFBundleDevelopmentRegion"] = "en"
    with info_path.open("wb") as handle:
        plistlib.dump(info, handle, sort_keys=False)


def _patch_existing_post_install(text: str) -> str:
    marker = "# CodeKey permissions and ML Kit settings."
    if marker in text:
        return text

    block = """    target.build_configurations.each do |config|
      # CodeKey permissions and ML Kit settings.
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
      config.build_settings['EXCLUDED_ARCHS[sdk=*]'] = 'armv7'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_BLUETOOTH=1',
      ]
    end
"""
    helper = re.search(
        r"^(\s*)flutter_additional_ios_build_settings\(target\)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if helper:
        indent = helper.group(1)
        adjusted = "\n".join(
            indent + line[4:] if line.startswith("    ") else line
            for line in block.rstrip().splitlines()
        ) + "\n"
        return text[: helper.end()] + "\n" + adjusted + text[helper.end() :].lstrip("\n")

    # Fallback for a customized Podfile with no standard Flutter helper call.
    post_install = re.search(r"post_install do \|installer\|\s*\n", text)
    if post_install:
        insertion = """  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
""" + block + "  end\n"
        return text[: post_install.end()] + insertion + text[post_install.end() :]

    return text.rstrip() + """

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      # CodeKey permissions and ML Kit settings.
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
      config.build_settings['EXCLUDED_ARCHS[sdk=*]'] = 'armv7'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_BLUETOOTH=1',
      ]
    end
  end
end
"""


def patch_ios_podfile() -> None:
    podfile = ROOT / "ios/Podfile"
    if not podfile.exists():
        raise FileNotFoundError("Generated iOS Podfile was not found")
    text = podfile.read_text(encoding="utf-8")
    if re.search(r"^platform :ios", text, flags=re.MULTILINE):
        text = re.sub(
            r"^platform :ios.*$",
            "platform :ios, '15.5'",
            text,
            flags=re.MULTILINE,
        )
    else:
        text = "platform :ios, '15.5'\n" + text

    chinese_pod = "  pod 'GoogleMLKit/TextRecognitionChinese', '~> 9.0.0'"
    if "GoogleMLKit/TextRecognitionChinese" not in text:
        match = re.search(r"target 'Runner' do\n", text)
        if match is None:
            raise RuntimeError("Runner target was not found in ios/Podfile")
        text = text[: match.end()] + chinese_pod + "\n" + text[match.end() :]

    text = _patch_existing_post_install(text)
    podfile.write_text(text, encoding="utf-8")


def patch_ios_project() -> None:
    project = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    if project.exists():
        text = project.read_text(encoding="utf-8")
        text = re.sub(
            r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
            "IPHONEOS_DEPLOYMENT_TARGET = 15.5;",
            text,
        )
        project.write_text(text, encoding="utf-8")

    framework_info = ROOT / "ios/Flutter/AppFrameworkInfo.plist"
    if framework_info.exists():
        with framework_info.open("rb") as handle:
            info = plistlib.load(handle)
        info["MinimumOSVersion"] = "15.5"
        with framework_info.open("wb") as handle:
            plistlib.dump(info, handle, sort_keys=False)


def patch_ios() -> None:
    patch_ios_info_plist()
    patch_ios_podfile()
    patch_ios_project()


def backup_sources(destination: Path) -> None:
    for relative in PRESERVE:
        source = ROOT / relative
        if not source.exists():
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)


def restore_sources(source_root: Path) -> None:
    for relative in PRESERVE:
        source = source_root / relative
        if not source.exists():
            continue
        target = ROOT / relative
        if target.exists():
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink()
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def main() -> int:
    if shutil.which("flutter") is None:
        print("Flutter SDK was not found in PATH.", file=sys.stderr)
        print("Install Flutter stable 3.38.1 or newer, then run this script again.", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="codekey-platforms-") as tmp:
        backup = Path(tmp)
        backup_sources(backup)
        run(
            "flutter",
            "create",
            "--overwrite",
            "--platforms=android,ios",
            "--android-language=kotlin",
            "--org",
            "ru.provolta",
            "--project-name",
            "codekey_app",
            ".",
        )
        restore_sources(backup)

    patch_android()
    patch_ios()
    run("flutter", "pub", "get")
    run("dart", "format", "lib", "test")

    print("\nAndroid and iOS runners generated successfully.")
    print("Android APK: flutter build apk --release")
    print("iOS archive: flutter build ipa --release --no-codesign")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
