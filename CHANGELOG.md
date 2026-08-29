# 0.3.2

- Replaced system `image_picker` camera flow with an in-app `camera` preview.
- A captured image returns immediately after the shutter press; there is no OEM camera confirmation step.
- The screenshot is inserted above the prompt before OCR starts.
- Added diagnostic events `camera.inline_ready`, `camera.inline_capture_started`, and `camera.inline_capture_completed`.

# 0.3.1

- Allow text-only LLM requests without screenshots.
- Keep new camera thumbnails visible immediately above the prompt while OCR runs.
- Pin ML Kit Text Recognition to 0.15.1 and add Android bitmap InputImage fallback for native OCR crashes.
- Keep one-tap keyboard-layout cycling on the main header and force immediate UI refresh through controller settings updates.
- Add OCR fallback diagnostic events.

# Changelog

## 0.3.0+3

### Платформы

- Возвращена единая кодовая база Android/iOS.
- Добавлен генератор обоих runner-проектов.
- Добавлены отдельные Android и iOS build scripts.
- iOS target установлен в 15.5, armv7 исключён.

### Камера и OCR

- Миниатюра появляется сразу после фотографирования.
- OCR запускается после добавления миниатюры и не блокирует её отображение.
- Добавлены состояния queued/processing/done/failed и прогресс.
- Добавлено удаление снимка крестиком.
- Добавлены повтор OCR и ручное редактирование после ошибки.
- Добавлена обработка `ImagePicker.retrieveLostData()`.
- Улучшены проверки отсутствующего и пустого файла.

### Настройки

- Язык интерфейса применяется сразу.
- Кнопка «Сохранить» возвращает на главный экран.
- USB-идентификация скрыта до подключения и авторизации ESP32.
- Поиск BLE теперь даёт видимый результат или ошибку.
- Раскладки стали настраиваемым списком.
- Иконка раскладки на главном экране переключает следующий профиль.

### API

- Добавлен отдельный DeepSeek API provider.
- DeepSeek использует JSON output и non-thinking mode для структурированного результата.
- Операционная система, редактор и язык программирования в API payload не добавляются.

### Диагностика

- Добавлен ротируемый локальный JSONL-журнал.
- Логируются этапы запуска, camera/OCR, BLE, DLP, API, job compile и HID-печати.
- Добавлен экспорт журнала через Android/iOS share sheet.
- Содержимое кода, запросов и секреты редактируются или исключаются.
