# CodeKey MVP security notes

## External API boundary

Photos remain local to the Android or iOS application sandbox. ML Kit OCR produces text on the phone. Only the reviewed user request and reviewed/redacted OCR text are sent to the configured external API.

The local DLP layer detects common private keys, JWTs, API tokens, credential assignments, connection strings, internal network addresses, email, phone numbers, IBAN, card-like values with Luhn validation, file paths, high-entropy contextual secrets and configured corporate terms.

This scanner is risk reduction, not proof that source code is non-confidential. The exact outbound payload is shown before every request.

## BLE authentication

The firmware authenticates the phone with HMAC-SHA256 using a unique per-device setup key. The simplified hardware has no pairing/reset button. A phone that proves possession of the setup key may replace the stored client ID. Only one BLE connection is accepted at a time.

The ESP32 remains discoverable whenever disconnected. Discoverability does not authorize commands: successful setup-key authentication is still required.

The preview protocol does not encrypt application payloads beyond whatever link-layer protection is provided by the BLE connection. A sensitive production deployment should add approved BLE bonding or authenticated application-layer encryption.

## Typing safety without buttons

- The Android/iOS app provides pause, resume and stop controls.
- BLE disconnect cancels the active job and releases all HID modifiers.
- ESP32 validates job length, CRC and every operation before execution.
- Code text is never parsed for hotkey markers.
- Power removal remains the final hardware stop mechanism because the product has no physical STOP button.

## API credentials

API keys and the ESP32 setup key are stored through `flutter_secure_storage`. Do not place keys in source files, screenshots, logs or build scripts.

## USB identity

The UI permits manual VID/PID changes because this is an explicit product requirement. The operator remains responsible for using identifiers permitted by applicable organizational and USB policies.
