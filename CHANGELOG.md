# CodeKey Android 0.2.0

- Android-only Flutter package; iOS runner removed.
- Added continuous discovery explanation for the button-free ESP32 firmware.
- Authentication uses the per-device setup key; a correctly authenticated new phone may replace the former client ID.
- Updated Android BLE permission handling for Android 11 and older and Android 12+.
- Android bootstrap enforces minSdk 24, adds camera/BLE permissions, Chinese ML Kit OCR model and optional release signing.
- Added root `BUILD_APK.bat` and `BUILD_APK.sh` wrappers.
- Retained the approved premium dark conversation UI, four interface languages, multiple OCR screenshots, local DLP and strict JSON LLM response.
