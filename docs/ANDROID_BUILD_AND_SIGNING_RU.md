# Сборка и подпись Android APK

## 1. Подготовка проекта

Установите Flutter 3.44 или новее (Dart 3.12 или новее) и Android Studio, затем из корня проекта выполните:

```bash
python tool/bootstrap_android.py
```

Скрипт создаёт только Android runner, добавляет разрешения камеры/BLE/Интернета, локальную китайскую модель ML Kit и поддержку пользовательской release-подписи.

## 2. Тестовая сборка

Windows:

```bat
tool\build_apk.bat
```

Linux/macOS:

```bash
./tool/build_apk.sh
```

Результат:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Пока `android/key.properties` отсутствует, шаблон использует debug key только для тестовой сборки.

## 3. Создание собственного ключа

Пример:

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Скопируйте шаблон:

```text
android/key.properties.example
```

в:

```text
android/key.properties
```

и укажите:

```properties
storePassword=ВАШ_ПАРОЛЬ
keyPassword=ВАШ_ПАРОЛЬ_КЛЮЧА
keyAlias=upload
storeFile=../upload-keystore.jks
```

Повторно выполните сборку. Не добавляйте `key.properties`, `.jks` и пароли в публичный репозиторий.

## 4. APK по архитектурам

При необходимости:

```bash
flutter build apk --release --split-per-abi
```
