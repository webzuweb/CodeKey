# Сборка и подпись CodeKey для iOS

## Требования

- macOS;
- Xcode 15.3 или новее;
- Flutter 3.38.1 или новее;
- CocoaPods;
- Apple Developer account для установки на обычные устройства и распространения.

## Подготовка проекта

```bash
python3 tool/bootstrap_platforms.py
```

Скрипт задаёт iOS 15.5, разрешения камеры/Bluetooth, ML Kit OCR и исключение armv7.

## Проверка

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```

## Неподписанный archive

```bash
./BUILD_IOS.sh
```

или:

```bash
flutter build ipa --release --no-codesign
```

## Настройка подписи

1. Откройте `ios/Runner.xcworkspace`.
2. Выберите target `Runner`.
3. Откройте `Signing & Capabilities`.
4. Укажите свою Team.
5. Замените Bundle Identifier на принадлежащий вам уникальный идентификатор.
6. Оставьте `Automatically manage signing` либо выберите profile вручную.
7. Выберите физическое устройство и выполните Run или Product → Archive.

## Разрешения Info.plist

Проект создаёт описания:

- `NSCameraUsageDescription`;
- `NSPhotoLibraryUsageDescription`;
- `NSBluetoothAlwaysUsageDescription`;
- `NSBluetoothPeripheralUsageDescription`.

Удалять их нельзя: камера, восстановление изображения и BLE используют эти возможности.

## ML Kit

Минимальная версия iOS — 15.5. ML Kit не поддерживает armv7, поэтому этот architecture исключён для всех конфигураций Pods и Runner.
