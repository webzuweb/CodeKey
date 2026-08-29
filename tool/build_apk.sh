#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is not available in PATH." >&2
  exit 2
fi

if [[ ! -f android/app/src/main/AndroidManifest.xml ]]; then
  python3 tool/bootstrap_android.py
fi

flutter pub get
flutter analyze
flutter test
flutter build apk --release "$@"

echo
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
