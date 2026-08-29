# CodeKey Mobile 0.3.1 — Android и iOS

Flutter-приложение для управления CodeKey ESP32-S3, который работает как USB HID-клавиатура. Смартфон фотографирует код, выполняет локальный OCR, проверяет текст перед отправкой во внешний API, показывает объяснение и передаёт подтверждённый код ESP32 по BLE.

## Что исправлено в 0.3.1

- возвращены обе мобильные платформы: Android и iOS;
- снимок появляется в ленте сразу после закрытия камеры, а OCR продолжается асинхронно;
- для каждого снимка показываются состояние и прогресс OCR;
- на миниатюре есть крестик удаления;
- при ошибке OCR можно повторить распознавание либо отредактировать текст вручную;
- добавлен перехват восстановленного снимка после уничтожения Android Activity;
- смена языка интерфейса применяется немедленно, без перезапуска;
- добавлен отдельный профиль DeepSeek API;
- нажатие на иконку раскладки в шапке мгновенно переключает следующий сохранённый профиль;
- в настройках можно создавать и удалять пользовательские раскладки;
- поиск ESP32 показывает индикатор, список результатов, пустой результат или локализованную ошибку;
- блок USB VID/PID показывается только после авторизованного подключения к ESP32;
- кнопка «Сохранить» сохраняет настройки и возвращает на главный экран;
- добавлен диагностический JSONL-журнал с ротацией и отправкой через системное меню Android/iOS.

## Основной сценарий

1. В настройках выбрать язык интерфейса, ОС, редактор, раскладки и внешний API.
2. Нажать «Найти устройства», выбрать ESP32 и ввести индивидуальный setup key.
3. На главном экране сделать один или несколько снимков кода.
4. Проверить OCR-текст по нажатию на миниатюру.
5. Ввести запрос пользователя.
6. Проверить локальный DLP-отчёт и точный замаскированный payload.
7. Отправить текст во внешний API.
8. Прочитать объяснение модели и проверить код.
9. Нажать «Печать»; только после этого приложение покажет, куда поставить курсор.
10. Подтвердить готовность и запустить ввод через ESP32.

## Данные внешнего API

Во внешний API передаются только:

- системная инструкция о строгом JSON-ответе;
- запрос пользователя;
- проверенный и при необходимости замаскированный OCR-текст.

Не передаются фотография, ОС, редактор, активная раскладка, ESP32 ID, VID/PID, скорость печати и диагностический журнал.

## Поддерживаемые API

- OpenAI-compatible Chat Completions;
- DeepSeek API;
- Anthropic Messages API.

Предустановка DeepSeek:

```text
Base URL: https://api.deepseek.com
Model:    deepseek-v4-flash
```

Поля URL и модели остаются редактируемыми.

## Требования к инструментам

Из-за используемой версии `share_plus` нужен Flutter 3.38.1 или новее и Dart 3.10 или новее. Для Android нужен Java 17. Для iOS нужны macOS, Xcode 15.3 или новее и deployment target iOS 15.5.

## Генерация Android и iOS runner

Исходный архив не фиксирует автоматически сгенерированные runner-файлы. Это уменьшает конфликты между версиями Flutter. После распаковки выполните:

```bash
python3 tool/bootstrap_platforms.py
```

На Windows:

```bat
tool\bootstrap_platforms.bat
```

Скрипт создаёт обе платформы и автоматически добавляет:

- Android camera/BLE permissions и `minSdk 24`;
- Android ML Kit Simplified Chinese OCR dependency;
- iOS camera/photo-library/Bluetooth usage descriptions;
- iOS deployment target 15.5 и исключение armv7;
- Chinese ML Kit pod;
- permission-handler macros для камеры и Bluetooth;
- шаблон Android release-подписи.

## Сборка Android APK

Windows:

```bat
BUILD_ANDROID.bat
```

macOS/Linux:

```bash
./BUILD_ANDROID.sh
```

Результат:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Подпись описана в `docs/ANDROID_BUILD_AND_SIGNING_RU.md`.

## Сборка iOS

Только на macOS:

```bash
./BUILD_IOS.sh
```

Скрипт создаёт неподписанный Xcode archive. Затем откройте:

```text
ios/Runner.xcworkspace
```

и задайте Apple Team, Bundle Identifier и подпись. Подробнее: `docs/IOS_BUILD_AND_SIGNING_RU.md`.

## Диагностический журнал

В настройках откройте **«Диагностика и журналы» → «Отправить журнал для отладки»**. Приложение создаст файл:

```text
CodeKey-diagnostics-<UTC>.jsonl
```

и откроет стандартное меню «Поделиться». Этот файл можно отправить в чат для анализа.

По умолчанию журнал не сохраняет:

- исходный код;
- OCR-текст;
- запрос пользователя;
- API key;
- setup key;
- bearer-токены;
- приватные ключи.

Журнал всё равно следует просмотреть перед отправкой. Подробнее: `docs/DIAGNOSTICS_RU.md`.

## ESP32

Мобильная версия 0.3.1 совместима с прошивкой CodeKey ESP32-S3 0.2.0 без кнопок и светодиодов. BLE UUID и бинарный job protocol не изменены.

## 0.3.1 OCR workaround

If Android ML Kit fails in its native file-input path, CodeKey retries OCR using an in-memory RGBA bitmap (`InputImage.fromBitmap`). Captured thumbnails are added to UI state before OCR starts. A request can also be sent without screenshots; in that mode no OCR source-code block is sent to the API.
