#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null 2>&1 || { echo "Flutter SDK is not available in PATH." >&2; exit 2; }
[[ -f android/app/src/main/AndroidManifest.xml ]] || python3 tool/bootstrap_platforms.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release "$@"
echo
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
