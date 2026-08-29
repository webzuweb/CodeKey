#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo "iOS build requires macOS and Xcode." >&2; exit 2; }
command -v flutter >/dev/null 2>&1 || { echo "Flutter SDK is not available in PATH." >&2; exit 2; }
[[ -f ios/Runner/Info.plist ]] || python3 tool/bootstrap_platforms.py
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --no-codesign "$@"
echo
echo "Unsigned iOS archive: build/ios/archive/Runner.xcarchive"
echo "Open ios/Runner.xcworkspace in Xcode to configure Team, bundle ID and signing."
