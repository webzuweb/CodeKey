import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_logger.dart';
import 'ble_service.dart';
import 'dlp_service.dart';
import 'job_protocol.dart';
import 'llm_service.dart';
import 'models.dart';
import 'ocr_service.dart';
import 'settings_store.dart';

class CodeKeyController extends ChangeNotifier {
  CodeKeyController({
    SettingsStore? settingsStore,
    CodeKeyBleService? bleService,
    OcrService? ocrService,
    DlpService? dlpService,
    LlmService? llmService,
    JobCompiler? jobCompiler,
    ImagePicker? imagePicker,
    AppLogger? logger,
  }) : _settingsStore = settingsStore ?? SettingsStore(),
       _bleService = bleService ?? CodeKeyBleService(),
       _ocrService = ocrService ?? OcrService(),
       _dlpService = dlpService ?? DlpService(),
       _llmService = llmService ?? LlmService(),
       _jobCompiler = jobCompiler ?? JobCompiler(),
       _imagePicker = imagePicker ?? ImagePicker(),
       _logger = logger ?? AppLogger.instance;

  final SettingsStore _settingsStore;
  final CodeKeyBleService _bleService;
  final OcrService _ocrService;
  final DlpService _dlpService;
  final LlmService _llmService;
  final JobCompiler _jobCompiler;
  final ImagePicker _imagePicker;
  final AppLogger _logger;

  AppSettings settings = const AppSettings();
  DeviceStatus deviceStatus = const DeviceStatus();
  List<ScreenshotItem> screenshots = const [];
  List<DiscoveredCodeKey> discoveredDevices = const [];
  LlmCodingResponse? response;
  bool initialized = false;
  bool processingApi = false;
  bool scanning = false;
  String? error;
  String lastUserRequest = '';
  StreamSubscription<DeviceStatus>? _deviceSubscription;

  Future<void> initialize() async {
    try {
      settings = await _settingsStore.load();
      _logger.info('controller.settings_loaded', {
        'language': settings.language.name,
        'os': settings.os.name,
        'editor': settings.editor.name,
        'layoutCount': settings.keyboardLayouts.length,
        'activeLayout': settings.activeKeyboardLayout.label,
        'apiProvider': settings.apiProvider.name,
        'hasApiKey': settings.apiKey.isNotEmpty,
        'hasSavedDevice': settings.bleDeviceId.isNotEmpty,
      });
      _deviceSubscription = _bleService.statusStream.listen((status) {
        deviceStatus = status;
        _logger.info('ble.status_changed', {
          'state': status.connectionState.name,
          'deviceName': status.deviceName,
          'message': status.message,
          'jobState': status.jobState,
          'completedSteps': status.completedSteps,
          'totalSteps': status.totalSteps,
        });
        notifyListeners();
      });
      initialized = true;
      notifyListeners();

      if (settings.bleDeviceId.isNotEmpty && settings.setupKey.isNotEmpty) {
        unawaited(connectSavedDevice(silent: true));
      }
      unawaited(_recoverLostCameraImage());
    } on Object catch (exception, stackTrace) {
      _logger.error(
        'controller.initialize_failed',
        exception,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _recoverLostCameraImage() async {
    try {
      final recovered = await _imagePicker.retrieveLostData();
      final files = recovered.files;
      if (files == null || files.isEmpty) return;
      _logger.info('camera.lost_data_recovered', {'count': files.length});
      for (final file in files) {
        await _addImageFile(file);
      }
    } on Object catch (exception, stackTrace) {
      _logger.error(
        'camera.lost_data_recovery_failed',
        exception,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    await _settingsStore.save(settings);
    _logger.info('settings.saved', {
      'language': settings.language.name,
      'os': settings.os.name,
      'editor': settings.editor.name,
      'layoutCount': settings.keyboardLayouts.length,
      'activeLayout': settings.activeKeyboardLayout.label,
      'charactersPerSecond': settings.charactersPerSecond,
      'humanized': settings.humanized,
      'apiProvider': settings.apiProvider.name,
      'apiHost': _safeHost(settings.apiBaseUrl),
      'apiModel': settings.apiModel,
      'hasApiKey': settings.apiKey.isNotEmpty,
      'hasSetupKey': settings.setupKey.isNotEmpty,
    });
    notifyListeners();
  }

  Future<void> updateInterfaceLanguage(InterfaceLanguage language) async {
    if (settings.language == language) return;
    await updateSettings(settings.copyWith(language: language));
    _logger.info('settings.language_changed', {'language': language.name});
  }

  Future<KeyboardLayoutOption> cycleKeyboardLayout() async {
    final layouts = settings.keyboardLayouts;
    if (layouts.isEmpty) return defaultKeyboardLayouts.first;
    final current = layouts.indexWhere(
      (item) => item.id == settings.activeKeyboardLayoutId,
    );
    final next = layouts[(current < 0 ? 0 : current + 1) % layouts.length];
    await updateSettings(settings.copyWith(activeKeyboardLayoutId: next.id));
    _logger.info('settings.layout_cycled', {
      'layoutId': next.id,
      'layoutCode': next.code,
      'baseProfile': next.baseProfile.name,
    });
    return next;
  }

  Future<void> addScreenshot() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      _logger.warning('camera.permission_denied', {'status': permission.name});
      throw const ControllerException('camera_permission_denied');
    }

    _logger.info('camera.capture_started');
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 94,
      requestFullMetadata: false,
    );
    if (image == null) {
      _logger.info('camera.capture_cancelled');
      return;
    }

    if (response != null) {
      await _clearScreenshotFiles();
      response = null;
      lastUserRequest = '';
      screenshots = const [];
      notifyListeners();
    }
    await _addImageFile(image);
  }

  Future<void> _addImageFile(XFile image) async {
    final random = Random.secure();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 30)}';

    // Add the original camera file before any copy or OCR work. This makes the
    // thumbnail appear immediately when the camera returns to the application.
    screenshots = [
      ...screenshots,
      ScreenshotItem(id: id, path: image.path),
    ];
    notifyListeners();
    _logger.info('camera.capture_added', {
      'screenshotId': id,
      'screenshotCount': screenshots.length,
      'extension': _extension(image.path),
    });

    unawaited(_persistAndRecognize(id, image));
  }

  Future<void> _persistAndRecognize(String id, XFile image) async {
    var path = image.path;
    try {
      final temporary = await getTemporaryDirectory();
      final directory = Directory(
        '${temporary.path}${Platform.pathSeparator}codekey-captures',
      );
      await directory.create(recursive: true);
      final extension = _extension(image.path).isEmpty ? '.jpg' : _extension(image.path);
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$id$extension',
      );
      if (destination.path != image.path) {
        await image.saveTo(destination.path);
        path = destination.path;
        _updateScreenshot(id, (item) => item.copyWith(path: path));
      }
    } on Object catch (exception, stackTrace) {
      // The original image_picker path is still usable in most cases.
      _logger.error(
        'camera.persist_failed',
        exception,
        stackTrace: stackTrace,
        data: {'screenshotId': id},
      );
    }
    if (!screenshots.any((item) => item.id == id)) {
      if (path != image.path) await _deletePath(path);
      _logger.info('camera.persist_discarded', {'screenshotId': id});
      return;
    }
    await _runOcr(id);
  }

  Future<void> _runOcr(String id) async {
    _updateScreenshot(
      id,
      (item) => item.copyWith(
        state: OcrState.processing,
        progress: 0.12,
        error: null,
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _updateScreenshot(id, (item) => item.copyWith(progress: 0.36));
      final item = screenshots.where((value) => value.id == id).firstOrNull;
      if (item == null) {
        _logger.info('ocr.discarded_before_start', {'screenshotId': id});
        return;
      }
      final file = File(item.path);
      if (!await file.exists()) throw const OcrException('image_file_missing');
      final size = await file.length();
      _updateScreenshot(id, (value) => value.copyWith(progress: 0.58));
      final text = await _ocrService.recognize(item.path, settings.language);
      if (text.trim().isEmpty) throw const OcrException('ocr_no_text_detected');
      if (!screenshots.any((value) => value.id == id)) {
        _logger.info('ocr.result_discarded', {'screenshotId': id});
        return;
      }
      _updateScreenshot(
        id,
        (value) => value.copyWith(
          ocrText: text,
          state: OcrState.done,
          progress: 1,
          error: null,
        ),
      );
      _logger.info('ocr.completed', {
        'screenshotId': id,
        'imageBytes': size,
        'durationMs': stopwatch.elapsedMilliseconds,
        'recognizedCharacters': text.length,
        'recognizedLines': '\n'.allMatches(text).length + 1,
      });
    } on Object catch (ocrError, stackTrace) {
      _updateScreenshot(
        id,
        (item) => item.copyWith(
          state: OcrState.failed,
          progress: 1,
          error: ocrError.toString(),
        ),
      );
      _logger.error(
        'ocr.failed',
        ocrError,
        stackTrace: stackTrace,
        data: {
          'screenshotId': id,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
    }
  }

  Future<void> retryOcr(String id) async {
    final exists = screenshots.any((item) => item.id == id);
    if (!exists) return;
    _logger.info('ocr.retry_requested', {'screenshotId': id});
    await _runOcr(id);
  }

  void editOcr(String id, String text) {
    _updateScreenshot(
      id,
      (item) => item.copyWith(
        ocrText: text,
        state: OcrState.done,
        progress: 1,
        error: null,
      ),
    );
    _logger.info('ocr.edited', {
      'screenshotId': id,
      'characters': text.length,
      'lines': '\n'.allMatches(text).length + 1,
    });
  }

  Future<void> removeScreenshot(String id) async {
    final item = screenshots.where((value) => value.id == id).firstOrNull;
    screenshots = screenshots
        .where((value) => value.id != id)
        .toList(growable: false);
    notifyListeners();
    _logger.info('camera.capture_removed', {
      'screenshotId': id,
      'remaining': screenshots.length,
    });
    if (item != null) await _deletePath(item.path);
  }

  void _updateScreenshot(
    String id,
    ScreenshotItem Function(ScreenshotItem item) update,
  ) {
    screenshots = screenshots
        .map((item) => item.id == id ? update(item) : item)
        .toList(growable: false);
    notifyListeners();
  }

  String get combinedCode => screenshots
      .where(
        (item) =>
            item.state == OcrState.done && item.ocrText.trim().isNotEmpty,
      )
      .map((item) => item.ocrText.trim())
      .join('\n\n');

  PreparedSubmission prepareSubmission(String userRequest) {
    final request = userRequest.trim();
    final code = combinedCode;
    if (request.isEmpty) throw const ControllerException('request_required');
    if (code.isEmpty) throw const ControllerException('code_required');
    if (screenshots.any(
      (item) =>
          item.state == OcrState.processing || item.state == OcrState.queued,
    )) {
      throw const ControllerException('ocr_still_running');
    }
    if (screenshots.any((item) => item.state == OcrState.failed)) {
      throw const ControllerException('ocr_contains_failed_items');
    }
    if (settings.apiBaseUrl.trim().isEmpty ||
        settings.apiModel.trim().isEmpty ||
        settings.apiKey.trim().isEmpty) {
      throw const ControllerException('api_not_configured');
    }

    final report = _dlpService.scan(
      request: request,
      code: code,
      corporateTerms: settings.corporateTerms,
    );
    final redacted = _dlpService.redact(
      request: request,
      code: code,
      report: report,
    );
    _logger.info('dlp.scan_completed', {
      'requestCharacters': request.length,
      'codeCharacters': code.length,
      'findingCount': report.findings.length,
      'criticalCount': report.findings
          .where((item) => item.severity == DlpSeverity.critical)
          .length,
      'highCount': report.findings
          .where((item) => item.severity == DlpSeverity.high)
          .length,
    });
    return PreparedSubmission(
      systemPrompt: LlmService.systemPrompt,
      userMessage: _llmService.buildUserMessage(
        request: redacted.request,
        code: redacted.code,
      ),
      report: report,
      redactedRequest: redacted.request,
      redactedCode: redacted.code,
    );
  }

  Future<void> submit(
    PreparedSubmission submission,
    String originalRequest,
  ) async {
    processingApi = true;
    error = null;
    lastUserRequest = originalRequest.trim();
    notifyListeners();
    final stopwatch = Stopwatch()..start();
    try {
      _logger.info('llm.request_started', {
        'provider': settings.apiProvider.name,
        'apiHost': _safeHost(settings.apiBaseUrl),
        'model': settings.apiModel,
        'requestCharacters': submission.redactedRequest.length,
        'codeCharacters': submission.redactedCode.length,
      });
      response = await _llmService.complete(
        settings: settings,
        request: submission.redactedRequest,
        code: submission.redactedCode,
      );
      _logger.info('llm.request_completed', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'explanationCharacters': response!.explanation.length,
        'codeCharacters': response!.code.length,
        'warningCount': response!.warnings.length,
        'operation': response!.operation.name,
      });
      await _clearScreenshotFiles();
      screenshots = const [];
    } on Object catch (apiError, stackTrace) {
      error = apiError.toString();
      _logger.error(
        'llm.request_failed',
        apiError,
        stackTrace: stackTrace,
        data: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'provider': settings.apiProvider.name,
          'apiHost': _safeHost(settings.apiBaseUrl),
          'model': settings.apiModel,
        },
      );
      rethrow;
    } finally {
      processingApi = false;
      notifyListeners();
    }
  }

  Future<void> _clearScreenshotFiles() async {
    for (final item in screenshots) {
      await _deletePath(item.path);
    }
  }

  Future<void> _deletePath(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Camera cache may already have removed the file.
    }
  }

  Future<void> startNewRequest() async {
    await _clearScreenshotFiles();
    response = null;
    lastUserRequest = '';
    screenshots = const [];
    error = null;
    notifyListeners();
    _logger.info('conversation.new_request');
  }

  Future<List<DiscoveredCodeKey>> scanDevices() async {
    scanning = true;
    error = null;
    discoveredDevices = const [];
    notifyListeners();
    final stopwatch = Stopwatch()..start();
    _logger.info('ble.scan_started');
    try {
      discoveredDevices = await _bleService.scan();
      _logger.info('ble.scan_completed', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'deviceCount': discoveredDevices.length,
        'devices': discoveredDevices
            .map((item) => {'name': item.name, 'rssi': item.rssi})
            .toList(growable: false),
      });
      return discoveredDevices;
    } on Object catch (scanError, stackTrace) {
      error = scanError.toString();
      _logger.error(
        'ble.scan_failed',
        scanError,
        stackTrace: stackTrace,
        data: {'durationMs': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> connectDevice(
    DiscoveredCodeKey device,
    String setupKey,
  ) async {
    final clientId = await _settingsStore.clientId();
    _logger.info('ble.connect_requested', {
      'deviceName': device.name,
      'rssi': device.rssi,
      'hasSetupKey': setupKey.isNotEmpty,
    });
    await _bleService.connect(
      deviceId: device.id,
      deviceName: device.name,
      setupKey: setupKey,
      clientId: clientId,
    );
    await updateSettings(
      settings.copyWith(
        bleDeviceId: device.id,
        bleDeviceName: device.name,
        setupKey: setupKey,
      ),
    );
  }

  Future<void> connectSavedDevice({bool silent = false}) async {
    if (settings.bleDeviceId.isEmpty || settings.setupKey.isEmpty) return;
    try {
      await connectDevice(
        DiscoveredCodeKey(
          id: settings.bleDeviceId,
          name: settings.bleDeviceName.isEmpty
              ? 'CodeKey'
              : settings.bleDeviceName,
          rssi: 0,
        ),
        settings.setupKey,
      );
    } on Object catch (connectError, stackTrace) {
      _logger.error(
        'ble.saved_device_connect_failed',
        connectError,
        stackTrace: stackTrace,
      );
      if (!silent) rethrow;
      error = connectError.toString();
      notifyListeners();
    }
  }

  Future<void> disconnectDevice() => _bleService.disconnect();

  Future<void> applyUsbIdentity() async {
    _logger.info('usb.identity_apply_requested', {
      'vid': settings.usbVid,
      'pid': settings.usbPid,
      'manufacturerLength': settings.usbManufacturer.length,
      'productLength': settings.usbProduct.length,
      'serialLength': settings.usbSerial.length,
    });
    await _bleService.configureUsb(settings);
  }

  CompiledJob compilePrintJob({
    required bool saveAfter,
    required bool formatAfter,
  }) {
    final result = response;
    if (result == null || result.code.isEmpty) {
      throw const ControllerException('no_code_to_print');
    }
    final after = <SemanticAction>[
      if (formatAfter) SemanticAction.formatDocument,
      if (saveAfter) SemanticAction.save,
    ];
    final job = _jobCompiler.compile(
      code: result.code,
      settings: settings,
      after: after,
    );
    _logger.info('typing.job_compiled', {
      'jobId': job.id,
      'payloadBytes': job.bytes.length,
      'totalSteps': job.totalSteps,
      'layout': settings.activeKeyboardLayout.label,
      'saveAfter': saveAfter,
      'formatAfter': formatAfter,
    });
    return job;
  }

  Future<void> startPrint(CompiledJob job) async {
    _logger.info('typing.job_start_requested', {
      'jobId': job.id,
      'payloadBytes': job.bytes.length,
      'totalSteps': job.totalSteps,
    });
    await _bleService.uploadAndStart(job, settings);
  }

  Future<void> pausePrint() => _bleService.pause();
  Future<void> resumePrint() => _bleService.resume();
  Future<void> stopPrint() => _bleService.cancel();

  Future<File> exportDiagnostics() => _logger.exportDiagnostics(
    metadata: {
      'language': settings.language.name,
      'os': settings.os.name,
      'editor': settings.editor.name,
      'layoutCount': settings.keyboardLayouts.length,
      'activeLayout': settings.activeKeyboardLayout.label,
      'apiProvider': settings.apiProvider.name,
      'apiHost': _safeHost(settings.apiBaseUrl),
      'apiModel': settings.apiModel,
      'hasApiKey': settings.apiKey.isNotEmpty,
      'deviceConnectionState': deviceStatus.connectionState.name,
      'deviceName': deviceStatus.deviceName,
      'jobState': deviceStatus.jobState,
      'screenshotCount': screenshots.length,
      'ocrStates': screenshots.map((item) => item.state.name).toList(growable: false),
    },
  );

  Future<void> clearDiagnostics() => _logger.clear();

  String _safeHost(String value) {
    try {
      return Uri.parse(value).host;
    } on FormatException {
      return '<invalid-url>';
    }
  }

  String _extension(String path) {
    final separator = path.lastIndexOf('.');
    if (separator < 0 || separator < path.lastIndexOf(Platform.pathSeparator)) {
      return '';
    }
    final extension = path.substring(separator).toLowerCase();
    return extension.length <= 6 ? extension : '';
  }

  @override
  void dispose() {
    unawaited(_deviceSubscription?.cancel());
    unawaited(_bleService.dispose());
    _llmService.dispose();
    unawaited(_logger.flush());
    super.dispose();
  }
}

class ControllerException implements Exception {
  const ControllerException(this.message);
  final String message;
  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
