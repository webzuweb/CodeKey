import 'dart:convert';

import 'package:flutter/foundation.dart';

const _unset = Object();

enum InterfaceLanguage { ru, en, es, zh }
enum ExternalApiProvider { openAiCompatible, deepSeek, anthropic }
enum WorkstationOs { windows, linux, macos }
enum EditorProfile { generic, vscode, jetBrains, visualStudio, androidStudio, xcode }
enum KeyboardLayoutProfile { enUs, enGb }
enum OcrState { queued, processing, done, failed }
enum CodeKeyConnectionState { disconnected, connecting, connected, authenticated, error }
enum DlpSeverity { low, medium, high, critical }
enum CodeOperation { insertAtCursor, replaceSelection, replaceFile, none }
enum SemanticAction {
  save,
  saveAs,
  newFile,
  closeFile,
  undo,
  redo,
  selectAll,
  find,
  formatDocument,
  commandPalette,
  enter,
  backspace,
  deleteForward,
  tab,
  outdent,
  escape,
}

@immutable
class KeyboardLayoutOption {
  const KeyboardLayoutOption({
    required this.id,
    required this.code,
    required this.name,
    required this.baseProfile,
    this.builtIn = false,
  });

  final String id;
  final String code;
  final String name;
  final KeyboardLayoutProfile baseProfile;
  final bool builtIn;

  String get label => code.trim().isEmpty ? name : code.toUpperCase();

  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'baseProfile': baseProfile.name,
    'builtIn': builtIn,
  };

  static KeyboardLayoutOption? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final id = map['id'] as String? ?? '';
    final code = map['code'] as String? ?? '';
    final name = map['name'] as String? ?? '';
    final profile = _enumByName(
      KeyboardLayoutProfile.values,
      map['baseProfile'],
    );
    if (id.trim().isEmpty || name.trim().isEmpty || profile == null) return null;
    return KeyboardLayoutOption(
      id: id.trim(),
      code: code.trim().isEmpty ? name.trim() : code.trim().toUpperCase(),
      name: name.trim(),
      baseProfile: profile,
      builtIn: map['builtIn'] as bool? ?? false,
    );
  }
}

const defaultKeyboardLayouts = <KeyboardLayoutOption>[
  KeyboardLayoutOption(
    id: 'en-us',
    code: 'EN-US',
    name: 'English — US',
    baseProfile: KeyboardLayoutProfile.enUs,
    builtIn: true,
  ),
  KeyboardLayoutOption(
    id: 'en-gb',
    code: 'EN-GB',
    name: 'English — UK',
    baseProfile: KeyboardLayoutProfile.enGb,
    builtIn: true,
  ),
];

@immutable
class AppSettings {
  const AppSettings({
    this.language = InterfaceLanguage.ru,
    this.os = WorkstationOs.windows,
    this.editor = EditorProfile.vscode,
    this.keyboardLayouts = defaultKeyboardLayouts,
    this.activeKeyboardLayoutId = 'en-us',
    this.charactersPerSecond = 8,
    this.humanized = true,
    this.apiProvider = ExternalApiProvider.openAiCompatible,
    this.apiBaseUrl = 'https://api.openai.com/v1',
    this.apiModel = '',
    this.apiKey = '',
    this.apiTimeoutSeconds = 90,
    this.corporateTerms = '',
    this.bleDeviceId = '',
    this.bleDeviceName = '',
    this.setupKey = '',
    this.usbVid = '303A',
    this.usbPid = '4001',
    this.usbManufacturer = 'PROVOLTA',
    this.usbProduct = 'CodeKey Keyboard',
    this.usbSerial = 'CK-000001',
  });

  final InterfaceLanguage language;
  final WorkstationOs os;
  final EditorProfile editor;
  final List<KeyboardLayoutOption> keyboardLayouts;
  final String activeKeyboardLayoutId;
  final int charactersPerSecond;
  final bool humanized;
  final ExternalApiProvider apiProvider;
  final String apiBaseUrl;
  final String apiModel;
  final String apiKey;
  final int apiTimeoutSeconds;
  final String corporateTerms;
  final String bleDeviceId;
  final String bleDeviceName;
  final String setupKey;
  final String usbVid;
  final String usbPid;
  final String usbManufacturer;
  final String usbProduct;
  final String usbSerial;

  KeyboardLayoutOption get activeKeyboardLayout {
    for (final layout in keyboardLayouts) {
      if (layout.id == activeKeyboardLayoutId) return layout;
    }
    return keyboardLayouts.isNotEmpty ? keyboardLayouts.first : defaultKeyboardLayouts.first;
  }

  KeyboardLayoutProfile get layout => activeKeyboardLayout.baseProfile;

  AppSettings copyWith({
    InterfaceLanguage? language,
    WorkstationOs? os,
    EditorProfile? editor,
    List<KeyboardLayoutOption>? keyboardLayouts,
    String? activeKeyboardLayoutId,
    int? charactersPerSecond,
    bool? humanized,
    ExternalApiProvider? apiProvider,
    String? apiBaseUrl,
    String? apiModel,
    String? apiKey,
    int? apiTimeoutSeconds,
    String? corporateTerms,
    String? bleDeviceId,
    String? bleDeviceName,
    String? setupKey,
    String? usbVid,
    String? usbPid,
    String? usbManufacturer,
    String? usbProduct,
    String? usbSerial,
  }) {
    final layouts = List<KeyboardLayoutOption>.unmodifiable(
      keyboardLayouts ?? this.keyboardLayouts,
    );
    final requestedActive = activeKeyboardLayoutId ?? this.activeKeyboardLayoutId;
    final resolvedActive = layouts.any((item) => item.id == requestedActive)
        ? requestedActive
        : (layouts.isNotEmpty ? layouts.first.id : defaultKeyboardLayouts.first.id);
    return AppSettings(
      language: language ?? this.language,
      os: os ?? this.os,
      editor: editor ?? this.editor,
      keyboardLayouts: layouts.isEmpty ? defaultKeyboardLayouts : layouts,
      activeKeyboardLayoutId: resolvedActive,
      charactersPerSecond: charactersPerSecond ?? this.charactersPerSecond,
      humanized: humanized ?? this.humanized,
      apiProvider: apiProvider ?? this.apiProvider,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiModel: apiModel ?? this.apiModel,
      apiKey: apiKey ?? this.apiKey,
      apiTimeoutSeconds: apiTimeoutSeconds ?? this.apiTimeoutSeconds,
      corporateTerms: corporateTerms ?? this.corporateTerms,
      bleDeviceId: bleDeviceId ?? this.bleDeviceId,
      bleDeviceName: bleDeviceName ?? this.bleDeviceName,
      setupKey: setupKey ?? this.setupKey,
      usbVid: usbVid ?? this.usbVid,
      usbPid: usbPid ?? this.usbPid,
      usbManufacturer: usbManufacturer ?? this.usbManufacturer,
      usbProduct: usbProduct ?? this.usbProduct,
      usbSerial: usbSerial ?? this.usbSerial,
    );
  }

  Map<String, Object?> toPersistedJson() => {
    'language': language.name,
    'os': os.name,
    'editor': editor.name,
    'keyboardLayouts': keyboardLayouts.map((item) => item.toJson()).toList(growable: false),
    'activeKeyboardLayoutId': activeKeyboardLayoutId,
    // Keep the legacy field so older builds can still open the settings file.
    'layout': layout.name,
    'charactersPerSecond': charactersPerSecond,
    'humanized': humanized,
    'apiProvider': apiProvider.name,
    'apiBaseUrl': apiBaseUrl,
    'apiModel': apiModel,
    'apiTimeoutSeconds': apiTimeoutSeconds,
    'corporateTerms': corporateTerms,
    'bleDeviceId': bleDeviceId,
    'bleDeviceName': bleDeviceName,
    'usbVid': usbVid,
    'usbPid': usbPid,
    'usbManufacturer': usbManufacturer,
    'usbProduct': usbProduct,
    'usbSerial': usbSerial,
  };

  static AppSettings fromPersistedJson(
    Map<String, Object?> json, {
    required String apiKey,
    required String setupKey,
  }) {
    final parsedLayouts = <KeyboardLayoutOption>[];
    final rawLayouts = json['keyboardLayouts'];
    if (rawLayouts is List) {
      for (final value in rawLayouts) {
        final parsed = KeyboardLayoutOption.fromJson(value);
        if (parsed != null && !parsedLayouts.any((item) => item.id == parsed.id)) {
          parsedLayouts.add(parsed);
        }
      }
    }

    var layouts = parsedLayouts;
    var activeId = json['activeKeyboardLayoutId'] as String? ?? '';
    if (layouts.isEmpty) {
      final legacy = _enumByName(KeyboardLayoutProfile.values, json['layout']) ??
          KeyboardLayoutProfile.enUs;
      layouts = List<KeyboardLayoutOption>.from(defaultKeyboardLayouts);
      activeId = legacy == KeyboardLayoutProfile.enGb ? 'en-gb' : 'en-us';
    }
    if (!layouts.any((item) => item.id == activeId)) activeId = layouts.first.id;

    return AppSettings(
      language: _enumByName(InterfaceLanguage.values, json['language']) ?? InterfaceLanguage.ru,
      os: _enumByName(WorkstationOs.values, json['os']) ?? WorkstationOs.windows,
      editor: _enumByName(EditorProfile.values, json['editor']) ?? EditorProfile.vscode,
      keyboardLayouts: List<KeyboardLayoutOption>.unmodifiable(layouts),
      activeKeyboardLayoutId: activeId,
      charactersPerSecond: (json['charactersPerSecond'] as num?)?.toInt() ?? 8,
      humanized: json['humanized'] as bool? ?? true,
      apiProvider: _enumByName(ExternalApiProvider.values, json['apiProvider']) ??
          ExternalApiProvider.openAiCompatible,
      apiBaseUrl: json['apiBaseUrl'] as String? ?? 'https://api.openai.com/v1',
      apiModel: json['apiModel'] as String? ?? '',
      apiKey: apiKey,
      apiTimeoutSeconds: (json['apiTimeoutSeconds'] as num?)?.toInt() ?? 90,
      corporateTerms: json['corporateTerms'] as String? ?? '',
      bleDeviceId: json['bleDeviceId'] as String? ?? '',
      bleDeviceName: json['bleDeviceName'] as String? ?? '',
      setupKey: setupKey,
      usbVid: json['usbVid'] as String? ?? '303A',
      usbPid: json['usbPid'] as String? ?? '4001',
      usbManufacturer: json['usbManufacturer'] as String? ?? 'PROVOLTA',
      usbProduct: json['usbProduct'] as String? ?? 'CodeKey Keyboard',
      usbSerial: json['usbSerial'] as String? ?? 'CK-000001',
    );
  }

  String encodePersisted() => jsonEncode(toPersistedJson());
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

@immutable
class ScreenshotItem {
  const ScreenshotItem({
    required this.id,
    required this.path,
    this.ocrText = '',
    this.state = OcrState.queued,
    this.progress = 0,
    this.error,
  });

  final String id;
  final String path;
  final String ocrText;
  final OcrState state;
  final double progress;
  final String? error;

  ScreenshotItem copyWith({
    String? path,
    String? ocrText,
    OcrState? state,
    double? progress,
    Object? error = _unset,
  }) => ScreenshotItem(
    id: id,
    path: path ?? this.path,
    ocrText: ocrText ?? this.ocrText,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

@immutable
class LlmCodingResponse {
  const LlmCodingResponse({
    required this.schemaVersion,
    required this.explanation,
    required this.placement,
    required this.operation,
    required this.code,
    required this.warnings,
  });

  final int schemaVersion;
  final String explanation;
  final String placement;
  final CodeOperation operation;
  final String code;
  final List<String> warnings;
}

@immutable
class DlpFinding {
  const DlpFinding({
    required this.source,
    required this.type,
    required this.severity,
    required this.start,
    required this.end,
    required this.value,
    required this.maskedPreview,
    required this.placeholder,
  });

  final String source;
  final String type;
  final DlpSeverity severity;
  final int start;
  final int end;
  final String value;
  final String maskedPreview;
  final String placeholder;
}

@immutable
class DlpReport {
  const DlpReport({required this.findings});
  final List<DlpFinding> findings;
  bool get hasCritical => findings.any((item) => item.severity == DlpSeverity.critical);
  bool get hasHigh => findings.any((item) => item.severity == DlpSeverity.high);
}

@immutable
class PreparedSubmission {
  const PreparedSubmission({
    required this.systemPrompt,
    required this.userMessage,
    required this.report,
    required this.redactedRequest,
    required this.redactedCode,
  });

  final String systemPrompt;
  final String userMessage;
  final DlpReport report;
  final String redactedRequest;
  final String redactedCode;
}

@immutable
class DiscoveredCodeKey {
  const DiscoveredCodeKey({required this.id, required this.name, required this.rssi});
  final String id;
  final String name;
  final int rssi;
}

@immutable
class DeviceStatus {
  const DeviceStatus({
    this.connectionState = CodeKeyConnectionState.disconnected,
    this.deviceId = '',
    this.deviceName = '',
    this.message = '',
    this.jobState = 'idle',
    this.completedSteps = 0,
    this.totalSteps = 0,
  });

  final CodeKeyConnectionState connectionState;
  final String deviceId;
  final String deviceName;
  final String message;
  final String jobState;
  final int completedSteps;
  final int totalSteps;

  bool get isReady => connectionState == CodeKeyConnectionState.authenticated;
  double get progress => totalSteps == 0
      ? 0
      : (completedSteps / totalSteps).clamp(0, 1).toDouble();

  DeviceStatus copyWith({
    CodeKeyConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    String? message,
    String? jobState,
    int? completedSteps,
    int? totalSteps,
  }) => DeviceStatus(
    connectionState: connectionState ?? this.connectionState,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    message: message ?? this.message,
    jobState: jobState ?? this.jobState,
    completedSteps: completedSteps ?? this.completedSteps,
    totalSteps: totalSteps ?? this.totalSteps,
  );
}
