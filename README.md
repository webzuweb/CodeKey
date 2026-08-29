# CodeKey

## Русская версия

**CodeKey** — аппаратно-программный комплекс, который позволяет использовать возможности внешних LLM для работы с кодом на компьютерах, где запрещена установка сторонних приложений или прямое подключение к внешним AI-сервисам.

Система состоит из двух частей:

- мобильного приложения на **Flutter** для Android и iOS;
- устройства на базе **ESP32-S3**, которое подключается к рабочей станции по USB и определяется как обычная HID-клавиатура.

### Как это работает

Пользователь фотографирует код с экрана рабочей станции через приложение CodeKey.

Распознавание текста выполняется локально на смартфоне с помощью **Google ML Kit Text Recognition v2**. Фотография не передаётся в LLM API.

После OCR пользователь может проверить и отредактировать распознанный код, написать свой запрос и отправить во внешний LLM API.

Приложение поддерживает внешние API:

- DeepSeek;
- OpenAI-compatible API;
- Anthropic API.

Перед отправкой выполняется локальная проверка текста на потенциально конфиденциальные данные: API-ключи, токены, пароли, приватные ключи, строки подключения, внутренние адреса, email, платёжные данные и другие чувствительные значения.

В LLM передаются только:

- запрос пользователя;
- распознанный и подтверждённый пользователем текст;
- системная инструкция для получения структурированного ответа.

LLM возвращает JSON с отдельными полями:

- объяснение изменений;
- инструкция пользователю;
- код для вставки;
- режим вставки;
- предупреждения.

Полученный код отображается в приложении. После нажатия кнопки **«Печать»** пользователь получает инструкцию, куда установить курсор или какой участок кода выделить.

Затем приложение передаёт готовое задание по Bluetooth Low Energy на ESP32-S3.

ESP32-S3 эмулирует стандартную USB-клавиатуру и вводит полученный код на рабочей станции через USB HID.

### Архитектура

```text
Рабочая станция
       ▲
       │ USB HID
       │
   ESP32-S3
       ▲
       │ BLE
       │
Android / iPhone
       │
       ├── Camera
       ├── ML Kit OCR
       ├── Local DLP
       ├── LLM API
       └── Job Compiler
              │
              ▼
        External LLM API
```

### Основные возможности

- Android и iOS;
- Flutter;
- ESP32-S3 USB HID Keyboard;
- Bluetooth Low Energy;
- несколько фотографий в одном запросе;
- локальный OCR;
- редактирование OCR-текста;
- запрос к LLM без фотографии;
- запрос к LLM вообще без OCR и скриншотов;
- DeepSeek API;
- OpenAI-compatible API;
- Anthropic API;
- строгий JSON-формат ответа LLM;
- локальная проверка конфиденциальных данных;
- пользовательские профили клавиатуры;
- выбор Windows, Linux или macOS;
- профили различных IDE;
- пользовательские раскладки клавиатуры;
- быстрое переключение раскладки с главного экрана;
- изменение USB VID/PID;
- изменение USB Manufacturer, Product и Serial;
- настройка скорости печати;
- режим естественного темпа печати;
- Pause / Resume / Stop;
- локальное логирование;
- экспорт диагностического журнала для отладки;
- русский, английский, испанский и китайский интерфейс.

### ESP32-S3

ESP32-S3 постоянно доступен для BLE-поиска, пока смартфон не подключён.

После подключения мобильное приложение может передавать:

- текст;
- HID-клавиши;
- комбинации клавиш;
- задержки;
- семантические команды.

Например:

```text
SAVE
SAVE_AS
NEW_FILE
CLOSE_FILE
UNDO
REDO
ENTER
TAB
BACKSPACE
DELETE
```

Конкретная комбинация клавиш определяется локально в зависимости от выбранной операционной системы и IDE.

Например:

```text
SAVE

Windows/Linux:
Ctrl + S

macOS:
Command + S
```

LLM никогда не управляет HID-командами напрямую.

Код и управляющие действия разделены на уровне протокола.

### OCR

Для распознавания используется **Google ML Kit Text Recognition v2**.

После создания фотографии:

1. снимок сразу отображается на основном экране;
2. OCR запускается асинхронно;
3. отображается статус обработки;
4. пользователь может открыть результат OCR;
5. распознанный код можно исправить вручную;
6. ненужный снимок можно удалить.

Поддерживаются несколько фотографий в одном запросе.

### Конфиденциальность

Изображения экрана не отправляются в LLM API.

До отправки текста выполняется локальная DLP-проверка.

Приложение ищет:

- API keys;
- access tokens;
- JWT;
- passwords;
- private keys;
- connection strings;
- внутренние IP;
- внутренние домены;
- email;
- телефонные номера;
- IBAN;
- номера банковских карт;
- потенциальные секреты с высокой энтропией;
- пользовательские корпоративные слова.

Перед отправкой пользователь может увидеть точное содержимое API-запроса.

### Формат ответа LLM

Модель получает инструкцию возвращать только JSON:

```json
{
  "schema_version": 1,
  "explanation": "Что исправлено и почему",
  "placement": "Куда установить курсор или какой участок выделить",
  "operation": "replace_selection",
  "code": "код для вставки",
  "warnings": []
}
```

Приложение валидирует ответ до создания задания для ESP32.

### Поддерживаемые платформы

#### Мобильное приложение

- Android
- iOS

#### Рабочая станция

Поскольку ESP32 определяется как стандартная USB HID-клавиатура, CodeKey может использоваться с:

- Windows;
- Linux;
- macOS;
- другими системами с поддержкой USB HID.

### Возможные сценарии применения

CodeKey предназначен для разрешённых сценариев работы в средах с ограниченным доступом к внешним сервисам, например:

- разработка ПО в закрытых корпоративных сетях;
- банковская разработка;
- защищённые рабочие станции;
- инфраструктурные команды;
- лаборатории;
- производственные сети;
- компьютеры, где невозможно устанавливать дополнительные приложения.

CodeKey не устанавливает программное обеспечение на рабочую станцию: для компьютера устройство выглядит как обычная USB-клавиатура.

### Статус проекта

Проект находится на стадии активного MVP.

Текущая архитектура включает:

```text
Flutter Mobile Application
        │
        │ BLE
        ▼
ESP32-S3 Firmware
        │
        │ USB HID
        ▼
Target Workstation
```

Планируемое развитие:

- улучшение OCR кода;
- дополнительные IDE-профили;
- пользовательский редактор HID-профилей;
- расширенная DLP;
- локальная история задач;
- безопасное обновление прошивки ESP32;
- корпоративная конфигурация;
- управление политиками через MDM;
- дополнительные LLM API;
- локальные LLM на смартфоне.

### Важно

Проект предназначен для использования только на системах, к которым пользователь имеет разрешённый доступ.

Организации могут ограничивать использование внешних USB HID-устройств, смартфонов, фотографирование экранов или передачу исходного кода сторонним API. Перед использованием CodeKey в корпоративной среде необходимо согласовать его применение с политиками информационной безопасности организации.

---

## English version

**CodeKey** is a hardware-software bridge designed to bring external LLM-assisted coding capabilities to workstations where installing third-party software or directly connecting to external AI services is restricted.

The system consists of two main components:

- a **Flutter** mobile application for Android and iOS;
- an **ESP32-S3** device connected to the target workstation as a standard USB HID keyboard.

### How it works

The user photographs source code displayed on the target workstation using the CodeKey mobile application.

Text recognition is performed locally on the smartphone using **Google ML Kit Text Recognition v2**. The original screenshot is not sent to the LLM API.

The user can review and edit the recognized code, enter a natural-language request, and submit the text to an external LLM API.

Supported external providers include:

- DeepSeek;
- OpenAI-compatible APIs;
- Anthropic API.

Before any data leaves the phone, CodeKey performs a local privacy and secret scan that can detect API keys, tokens, passwords, private keys, connection strings, internal infrastructure addresses, email addresses, payment data, and other potentially sensitive values.

Only the following information is sent to the LLM:

- the user's request;
- the OCR text reviewed by the user;
- a system instruction defining the required structured response.

The model must return a JSON response containing separate fields for:

- explanation;
- placement instructions;
- generated code;
- insertion mode;
- warnings.

The response is displayed on the smartphone.

After the user presses **Print**, CodeKey displays instructions explaining where the cursor should be placed or which code block should be selected.

The mobile application then sends a keyboard job over Bluetooth Low Energy to the ESP32-S3.

The ESP32-S3 acts as a standard USB HID keyboard and types the generated code directly into the target workstation.

### Architecture

```text
Target Workstation
        ▲
        │ USB HID
        │
    ESP32-S3
        ▲
        │ BLE
        │
 Android / iPhone
        │
        ├── Camera
        ├── ML Kit OCR
        ├── Local DLP
        ├── LLM API
        └── Job Compiler
               │
               ▼
         External LLM API
```

### Main features

- Android and iOS;
- Flutter;
- ESP32-S3 USB HID keyboard;
- Bluetooth Low Energy;
- multiple screenshots per request;
- local OCR;
- editable OCR results;
- text-only requests without screenshots;
- DeepSeek API;
- OpenAI-compatible APIs;
- Anthropic API;
- strict JSON LLM responses;
- local confidential-data detection;
- keyboard profiles;
- Windows, Linux and macOS profiles;
- IDE-specific keyboard shortcuts;
- custom keyboard layouts;
- instant keyboard-layout switching from the main screen;
- configurable USB VID/PID;
- configurable USB Manufacturer, Product and Serial strings;
- adjustable typing speed;
- paced human-readable typing mode;
- Pause / Resume / Stop;
- local diagnostic logging;
- exportable debugging logs;
- Russian, English, Spanish and Simplified Chinese UI.

### ESP32-S3

The ESP32-S3 remains discoverable over Bluetooth while no smartphone is connected.

The mobile application can send structured operations including:

- text;
- HID key presses;
- keyboard shortcuts;
- delays;
- semantic editor actions.

Example semantic actions:

```text
SAVE
SAVE_AS
NEW_FILE
CLOSE_FILE
UNDO
REDO
ENTER
TAB
BACKSPACE
DELETE
```

The actual keyboard shortcut is resolved locally according to the selected operating system and editor profile.

For example:

```text
SAVE

Windows/Linux:
Ctrl + S

macOS:
Command + S
```

The LLM never controls HID commands directly.

Generated text and keyboard-control operations are separated at the protocol level.

### OCR

CodeKey uses **Google ML Kit Text Recognition v2** for on-device OCR.

After a photo is taken:

1. the screenshot is immediately displayed in the main interface;
2. OCR starts asynchronously;
3. processing progress is displayed;
4. the OCR result can be opened;
5. recognized code can be edited manually;
6. unwanted screenshots can be removed.

Multiple screenshots can be attached to a single request.

### Privacy

Original screenshots are not sent to the LLM API.

Before sending text, CodeKey runs a local DLP-style scan.

It can detect:

- API keys;
- access tokens;
- JWTs;
- passwords;
- private keys;
- database connection strings;
- internal IP addresses;
- internal domains;
- email addresses;
- telephone numbers;
- IBANs;
- payment card numbers;
- high-entropy strings that may represent secrets;
- organization-specific keywords.

The user can preview the exact payload before it is sent to the external API.

### LLM response format

The model is instructed to return only a structured JSON object:

```json
{
  "schema_version": 1,
  "explanation": "What was changed and why",
  "placement": "Where the cursor should be placed or what code should be selected",
  "operation": "replace_selection",
  "code": "exact code to type",
  "warnings": []
}
```

The application validates the response before creating a keyboard job.

### Supported platforms

#### Mobile application

- Android
- iOS

#### Target workstation

Because CodeKey appears as a standard USB HID keyboard, it can work with:

- Windows;
- Linux;
- macOS;
- other systems supporting USB HID keyboards.

### Example use cases

CodeKey is designed for authorized environments where direct AI integration is restricted, including:

- software development inside closed corporate networks;
- banking software development;
- protected workstations;
- infrastructure teams;
- research laboratories;
- industrial networks;
- computers where installing additional software is prohibited.

Nothing needs to be installed on the target workstation.

From the workstation's perspective, the ESP32-S3 is simply a USB keyboard.

### Project status

CodeKey is currently an active MVP.

Current architecture:

```text
Flutter Mobile Application
        │
        │ BLE
        ▼
ESP32-S3 Firmware
        │
        │ USB HID
        ▼
Target Workstation
```

Planned development includes:

- improved source-code OCR;
- additional IDE profiles;
- user-editable HID profiles;
- extended local DLP;
- local task history;
- secure ESP32 firmware updates;
- enterprise configuration profiles;
- MDM policy support;
- additional LLM providers;
- optional local LLM execution on mobile devices.

### Important

CodeKey is intended only for systems and environments where the user is authorized to operate.

Organizations may prohibit external USB HID devices, smartphones, screen photography, or sending source code to third-party APIs. Always ensure that CodeKey usage complies with the security and data-handling policies of the organization operating the target workstation.
