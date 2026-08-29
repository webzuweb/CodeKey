# Сборка и подпись CodeKey для Android

## Требования

- Flutter 3.38.1 или новее;
- Dart 3.10 или новее;
- Android Studio и Android SDK;
- Java 17;
- Python 3.

## Генерация Android/iOS runner

```bat
python tool\bootstrap_platforms.py
```

## Создание upload keystore

```bat
keytool -genkeypair -v ^
  -keystore upload-keystore.jks ^
  -storetype JKS ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000 ^
  -alias upload
```

Скопируйте:

```text
android/key.properties.example
```

в:

```text
android/key.properties
```

и заполните:

```properties
storePassword=ВАШ_ПАРОЛЬ
keyPassword=ВАШ_ПАРОЛЬ_КЛЮЧА
keyAlias=upload
storeFile=../upload-keystore.jks
```

Не добавляйте `.jks` и `key.properties` в публичный репозиторий.

## Сборка

```bat
BUILD_ANDROID.bat
```

Результат:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Для Google Play:

```bat
flutter build appbundle --release
```
