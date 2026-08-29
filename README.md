# CodeKey Android application 0.2.0

Android-only Flutter controller for the CodeKey ESP32-S3 USB HID keyboard bridge.

## Implemented flow

1. Find a CodeKey ESP32-S3 over BLE. The firmware stays discoverable while no phone is connected.
2. Authenticate with the individual setup key stored in Android Keystore-backed secure storage.
3. Take several workstation-screen photos.
4. Run ML Kit Text Recognition v2 locally on each photo.
5. Tap any thumbnail to review and edit the OCR text.
6. Enter the user request.
7. Run the local DLP scan and inspect the exact masked external-API payload.
8. Call an OpenAI-compatible or Anthropic external API.
9. Validate the strict JSON response: explanation, cursor placement, operation, code and warnings.
10. Show the explanation above the code. Screenshots are hidden after a successful response.
11. Only after the user taps **Печать / Print**, show the cursor-placement instruction.
12. Compile the approved code and local editor/OS hotkeys into allowlisted HID records, upload them over BLE and start after a countdown.

## Interface

- Premium dark ChatGPT-like conversation screen.
- Russian, English, Spanish and Simplified Chinese.
- Settings are on a separate page.
- Header contains only device status, keyboard layout and Settings.
- Several OCR screenshots per request.
- Editable OCR popup.
- No recent-actions or quick-actions sections.

## ESP32 connection behavior

- No hardware pairing button is expected.
- No hardware STOP button or status LED is expected.
- The ESP32 advertises continuously until a smartphone connects.
- A new smartphone with the correct setup key can authenticate and replace the stored client ID.
- Only one BLE connection is accepted at a time.
- Disconnecting BLE cancels the active typing job and releases all keys.

## Android project generation

The archive requires Flutter 3.44 or newer (Dart 3.12 or newer). It contains the Flutter sources and an Android-only bootstrap script. It deliberately generates the Android runner using the locally installed Flutter SDK, so Gradle files match that SDK revision.

```bash
python tool/bootstrap_android.py
```

Then build with:

```bash
flutter build apk --release
```

or use:

```text
Windows: tool\build_apk.bat
Linux:   ./tool/build_apk.sh
```

The build scripts run `flutter analyze`, tests and release APK compilation.

## Signing

See:

```text
docs/ANDROID_BUILD_AND_SIGNING_RU.md
```

After bootstrap, copy `android/key.properties.example` to `android/key.properties`, provide your private keystore values and rebuild. Without that file, the generated template uses debug signing for a test release build.

## External API data

The API receives only:

- the system JSON-output instruction;
- the user's request;
- reviewed and locally redacted OCR text.

The photo, operating system, editor, layout, ESP32 ID and VID/PID are not sent to the LLM API.

## Important limitation

Technical DLP can detect likely secrets, tokens, credentials, internal hosts and personal data, but it cannot prove that ordinary source code is not confidential intellectual property. The application therefore also shows the exact outbound payload and requires user confirmation.
