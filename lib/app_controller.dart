import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
  }) : _settingsStore = settingsStore ?? SettingsStore(),
       _bleService = bleService ?? CodeKeyBleService(),
       _ocrService = ocrService ?? OcrService(),
       _dlpService = dlpService ?? DlpService(),
       _llmService = llmService ?? LlmService(),
       _jobCompiler = jobCompiler ?? JobCompiler(),
       _imagePicker = imagePicker ?? ImagePicker();

  final SettingsStore _settingsStore;
  final CodeKeyBleService _bleService;
  final OcrService _ocrService;
  final DlpService _dlpService;
  final LlmService _llmService;
  final JobCompiler _jobCompiler;
  final ImagePicker _imagePicker;

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
    settings = await _settingsStore.load();
    _deviceSubscription = _bleService.statusStream.listen((status) {
      deviceStatus = status;
      notifyListeners();
    });
    initialized = true;
    notifyListeners();

    if (settings.bleDeviceId.isNotEmpty && settings.setupKey.isNotEmpty) {
      unawaited(connectSavedDevice(silent: true));
    }
    unawaited(_recoverLostCameraImage());
  }

  Future<void> _recoverLostCameraImage() async {
    try {
      final recovered = await _imagePicker.retrieveLostData();
      final files = recovered.files;
      if (files == null) return;
      for (final file in files) {
        await _addImageFile(file);
      }
    } on Object {
      // Lost-data recovery is best effort only.
    }
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    await _settingsStore.save(settings);
    notifyListeners();
  }

  Future<void> addScreenshot() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) throw const ControllerException('camera_permission_denied');
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 94,
      requestFullMetadata: false,
    );
    if (image == null) return;
    if (response != null) {
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
    screenshots = [
      ...screenshots,
      ScreenshotItem(id: id, path: image.path),
    ];
    notifyListeners();
    unawaited(_runOcr(id));
  }

  Future<void> _runOcr(String id) async {
    _updateScreenshot(id, (item) => item.copyWith(
      state: OcrState.processing,
      progress: 0.15,
      error: null,
    ));
    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _updateScreenshot(id, (item) => item.copyWith(progress: 0.55));
      final item = screenshots.firstWhere((value) => value.id == id);
      final text = await _ocrService.recognize(item.path, settings.language);
      _updateScreenshot(id, (value) => value.copyWith(
        ocrText: text,
        state: OcrState.done,
        progress: 1,
        error: null,
      ));
    } on Object catch (ocrError) {
      _updateScreenshot(id, (item) => item.copyWith(
        state: OcrState.failed,
        progress: 1,
        error: ocrError.toString(),
      ));
    }
  }

  void editOcr(String id, String text) {
    _updateScreenshot(id, (item) => item.copyWith(
      ocrText: text,
      state: OcrState.done,
      progress: 1,
      error: null,
    ));
  }

  Future<void> removeScreenshot(String id) async {
    final item = screenshots.where((value) => value.id == id).firstOrNull;
    screenshots = screenshots.where((value) => value.id != id).toList(growable: false);
    notifyListeners();
    if (item != null && item.path.isNotEmpty) {
      try {
        await File(item.path).delete();
      } on FileSystemException {
        // Camera cache may already have removed the file.
      }
    }
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
      .where((item) => item.state == OcrState.done && item.ocrText.trim().isNotEmpty)
      .map((item) => item.ocrText.trim())
      .join('\n\n');

  PreparedSubmission prepareSubmission(String userRequest) {
    final request = userRequest.trim();
    final code = combinedCode;
    if (request.isEmpty) throw const ControllerException('request_required');
    if (code.isEmpty) throw const ControllerException('code_required');
    if (screenshots.any((item) => item.state == OcrState.processing || item.state == OcrState.queued)) {
      throw const ControllerException('ocr_still_running');
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

  Future<void> submit(PreparedSubmission submission, String originalRequest) async {
    processingApi = true;
    error = null;
    lastUserRequest = originalRequest.trim();
    notifyListeners();
    try {
      response = await _llmService.complete(
        settings: settings,
        request: submission.redactedRequest,
        code: submission.redactedCode,
      );
      await _deleteOriginalImagesAfterResponse();
    } on Object catch (apiError) {
      error = apiError.toString();
      rethrow;
    } finally {
      processingApi = false;
      notifyListeners();
    }
  }

  Future<void> _deleteOriginalImagesAfterResponse() async {
    for (final item in screenshots) {
      if (item.path.isEmpty) continue;
      try {
        await File(item.path).delete();
      } on FileSystemException {
        // It can already be gone from the OS cache.
      }
    }
    screenshots = screenshots
        .map((item) => item.copyWith(path: ''))
        .toList(growable: false);
  }

  void startNewRequest() {
    response = null;
    lastUserRequest = '';
    screenshots = const [];
    error = null;
    notifyListeners();
  }

  Future<List<DiscoveredCodeKey>> scanDevices() async {
    scanning = true;
    error = null;
    notifyListeners();
    try {
      discoveredDevices = await _bleService.scan();
      return discoveredDevices;
    } on Object catch (scanError) {
      error = scanError.toString();
      rethrow;
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> connectDevice(DiscoveredCodeKey device, String setupKey) async {
    final clientId = await _settingsStore.clientId();
    await _bleService.connect(
      deviceId: device.id,
      deviceName: device.name,
      setupKey: setupKey,
      clientId: clientId,
    );
    await updateSettings(settings.copyWith(
      bleDeviceId: device.id,
      bleDeviceName: device.name,
      setupKey: setupKey,
    ));
  }

  Future<void> connectSavedDevice({bool silent = false}) async {
    if (settings.bleDeviceId.isEmpty || settings.setupKey.isEmpty) return;
    try {
      await connectDevice(
        DiscoveredCodeKey(
          id: settings.bleDeviceId,
          name: settings.bleDeviceName.isEmpty ? 'CodeKey' : settings.bleDeviceName,
          rssi: 0,
        ),
        settings.setupKey,
      );
    } on Object catch (connectError) {
      if (!silent) rethrow;
      error = connectError.toString();
      notifyListeners();
    }
  }

  Future<void> disconnectDevice() => _bleService.disconnect();

  Future<void> applyUsbIdentity() => _bleService.configureUsb(settings);

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
    return _jobCompiler.compile(
      code: result.code,
      settings: settings,
      after: after,
    );
  }

  Future<void> startPrint(CompiledJob job) => _bleService.uploadAndStart(job, settings);
  Future<void> pausePrint() => _bleService.pause();
  Future<void> resumePrint() => _bleService.resume();
  Future<void> stopPrint() => _bleService.cancel();

  @override
  void dispose() {
    unawaited(_deviceSubscription?.cancel());
    unawaited(_bleService.dispose());
    _llmService.dispose();
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
