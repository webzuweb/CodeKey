#!/usr/bin/env python3
"""Generate an Android runner matched to the locally installed Flutter SDK.

The archive keeps the Flutter application sources portable. Running this script
creates fresh Android platform files, then applies CodeKey camera, BLE, OCR and
optional release-signing configuration.
"""

from __future__ import annotations

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
]


def run(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


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
    """Set minSdk 24, required by the current Android image picker stack."""
    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        if path.suffix == ".kts":
            replacements = [
                ("minSdk = flutter.minSdkVersion", "minSdk = 24"),
                ("minSdk = 21", "minSdk = 24"),
                ("minSdk = 23", "minSdk = 24"),
            ]
        else:
            replacements = [
                ("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24"),
                ("minSdk flutter.minSdkVersion", "minSdk 24"),
                ("minSdkVersion 21", "minSdkVersion 24"),
                ("minSdkVersion 23", "minSdkVersion 24"),
            ]
        for old, new in replacements:
            if old in text:
                text = text.replace(old, new, 1)
                break
        if text == original and ("minSdk = 24" not in text and "minSdkVersion 24" not in text and "minSdk 24" not in text):
            raise RuntimeError(f"Could not set Android minSdk in {path}")
        path.write_text(text, encoding="utf-8")
        return
    raise FileNotFoundError("Generated Android app Gradle file was not found")

def patch_android_dependencies() -> None:
    """Bundle the on-device Simplified Chinese ML Kit recognizer."""
    dependency = "com.google.mlkit:text-recognition-chinese:16.0.1"
    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if dependency in text:
            return
        if path.suffix == ".kts":
            block = (
                "\n\ndependencies {\n"
                f'    implementation("{dependency}")\n'
                "}\n"
            )
        else:
            block = (
                "\n\ndependencies {\n"
                f"    implementation '{dependency}'\n"
                "}\n"
            )
        path.write_text(text.rstrip() + block, encoding="utf-8")
        return
    raise FileNotFoundError("Generated Android app Gradle file was not found")


def patch_kotlin_signing(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "CodeKey optional release signing" in text:
        return

    imports = "import java.io.FileInputStream\nimport java.util.Properties\n\n"
    if "import java.util.Properties" not in text:
        text = imports + text

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

    debug_patterns = [
        "            signingConfig signingConfigs.debug",
        "            signingConfig = signingConfigs.debug",
    ]
    signed_line = (
        "            signingConfig = keystorePropertiesFile.exists() ? "
        "signingConfigs.release : signingConfigs.debug"
    )
    for pattern in debug_patterns:
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

    example = ROOT / "android/key.properties.example"
    example.write_text(
        "storePassword=CHANGE_ME\n"
        "keyPassword=CHANGE_ME\n"
        "keyAlias=upload\n"
        "storeFile=../upload-keystore.jks\n",
        encoding="utf-8",
    )


def main() -> int:
    if shutil.which("flutter") is None:
        print("Flutter SDK was not found in PATH.", file=sys.stderr)
        print("Install Flutter stable, then run this script again.", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="codekey-android-") as tmp:
        backup = Path(tmp)
        for relative in PRESERVE:
            source = ROOT / relative
            if not source.exists():
                continue
            destination = backup / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, destination)
            else:
                shutil.copy2(source, destination)

        run(
            "flutter",
            "create",
            "--overwrite",
            "--platforms=android",
            "--android-language=kotlin",
            "--org",
            "ru.provolta",
            "--project-name",
            "codekey_app",
            ".",
        )

        for relative in PRESERVE:
            source = backup / relative
            if not source.exists():
                continue
            destination = ROOT / relative
            if destination.exists():
                if destination.is_dir():
                    shutil.rmtree(destination)
                else:
                    destination.unlink()
            if source.is_dir():
                shutil.copytree(source, destination)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)

    patch_android_manifest()
    patch_android_min_sdk()
    patch_android_dependencies()
    patch_android_signing()
    run("flutter", "pub", "get")
    run("flutter", "format", "lib", "test")
    print("\nAndroid runner generated successfully.")
    print("Test:  flutter test")
    print("Build: flutter build apk --release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
