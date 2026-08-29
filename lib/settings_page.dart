import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_controller.dart';
import 'controller_scope.dart';
import 'localization.dart';
import 'models.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _initialized = false;
  bool _showApiKey = false;
  bool _saving = false;
  bool _hasScanned = false;
  bool _sharingLogs = false;

  late InterfaceLanguage _language;
  late WorkstationOs _os;
  late EditorProfile _editor;
  late List<KeyboardLayoutOption> _keyboardLayouts;
  late String _activeLayoutId;
  late double _speed;
  late bool _humanized;
  late ExternalApiProvider _apiProvider;

  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _timeout = TextEditingController();
  final _corporateTerms = TextEditingController();
  final _setupKey = TextEditingController();
  final _vid = TextEditingController();
  final _pid = TextEditingController();
  final _manufacturer = TextEditingController();
  final _product = TextEditingController();
  final _serial = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final settings = CodeKeyScope.read(context).settings;
    _language = settings.language;
    _os = settings.os;
    _editor = settings.editor;
    _keyboardLayouts = List<KeyboardLayoutOption>.from(settings.keyboardLayouts);
    _activeLayoutId = settings.activeKeyboardLayoutId;
    _speed = settings.charactersPerSecond.toDouble();
    _humanized = settings.humanized;
    _apiProvider = settings.apiProvider;
    _baseUrl.text = settings.apiBaseUrl;
    _model.text = settings.apiModel;
    _apiKey.text = settings.apiKey;
    _timeout.text = '${settings.apiTimeoutSeconds}';
    _corporateTerms.text = settings.corporateTerms;
    _setupKey.text = settings.setupKey;
    _vid.text = settings.usbVid;
    _pid.text = settings.usbPid;
    _manufacturer.text = settings.usbManufacturer;
    _product.text = settings.usbProduct;
    _serial.text = settings.usbSerial;
    _initialized = true;
  }

  @override
  void dispose() {
    for (final controller in [
      _baseUrl,
      _model,
      _apiKey,
      _timeout,
      _corporateTerms,
      _setupKey,
      _vid,
      _pid,
      _manufacturer,
      _product,
      _serial,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = CodeKeyScope.of(context);
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(strings.t('settings')),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : () => _save(context, controller),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(strings.t('save')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [Color(0xFF111A38), CodeKeyTheme.background],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _SettingsSection(
              icon: Icons.language,
              title: strings.t('interface'),
              children: [
                DropdownButtonFormField<InterfaceLanguage>(
                  key: ValueKey('language-${_language.name}'),
                  initialValue: _language,
                  decoration: InputDecoration(
                    labelText: strings.t('interfaceLanguage'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: InterfaceLanguage.ru,
                      child: Text('Русский'),
                    ),
                    DropdownMenuItem(
                      value: InterfaceLanguage.en,
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: InterfaceLanguage.es,
                      child: Text('Español'),
                    ),
                    DropdownMenuItem(
                      value: InterfaceLanguage.zh,
                      child: Text('简体中文'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null || value == _language) return;
                    setState(() => _language = value);
                    await controller.updateInterfaceLanguage(value);
                  },
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.computer_outlined,
              title: strings.t('workstation'),
              children: [
                DropdownButtonFormField<WorkstationOs>(
                  initialValue: _os,
                  decoration: InputDecoration(
                    labelText: strings.t('operatingSystem'),
                  ),
                  items: WorkstationOs.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_osLabel(value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _os = value ?? _os),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EditorProfile>(
                  initialValue: _editor,
                  decoration: InputDecoration(labelText: strings.t('editor')),
                  items: EditorProfile.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_editorLabel(value, strings)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => _editor = value ?? _editor),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.keyboard_alt_outlined,
              title: strings.t('keyboardLayouts'),
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('layout-$_activeLayoutId-${_keyboardLayouts.length}'),
                  initialValue: _activeLayoutId,
                  decoration: InputDecoration(
                    labelText: strings.t('activeKeyboardLayout'),
                  ),
                  items: _keyboardLayouts
                      .map(
                        (layout) => DropdownMenuItem(
                          value: layout.id,
                          child: Text('${layout.code} — ${layout.name}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => _activeLayoutId = value);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  strings.t('layoutHelp'),
                  style: const TextStyle(
                    color: CodeKeyTheme.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ..._keyboardLayouts.map(
                  (layout) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(13, 9, 7, 9),
                    decoration: BoxDecoration(
                      color: CodeKeyTheme.surfaceHigh,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: layout.id == _activeLayoutId
                            ? CodeKeyTheme.primary
                            : CodeKeyTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: CodeKeyTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            layout.code,
                            style: const TextStyle(
                              color: CodeKeyTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(layout.name),
                              Text(
                                _baseLayoutLabel(layout.baseProfile),
                                style: const TextStyle(
                                  color: CodeKeyTheme.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!layout.builtIn)
                          IconButton(
                            tooltip: strings.t('deleteLayout'),
                            onPressed: () => _deleteLayout(layout),
                            icon: const Icon(Icons.close, size: 19),
                          ),
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addLayout,
                  icon: const Icon(Icons.add),
                  label: Text(strings.t('addLayout')),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.speed_outlined,
              title: strings.t('typing'),
              children: [
                Text(strings.t('typingSpeed', {'value': _speed.round()})),
                Slider(
                  min: 2,
                  max: 30,
                  divisions: 28,
                  value: _speed,
                  label: '${_speed.round()}',
                  onChanged: (value) => setState(() => _speed = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _humanized,
                  onChanged: (value) => setState(() => _humanized = value),
                  title: Text(strings.t('humanized')),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.cloud_outlined,
              title: strings.t('api'),
              children: [
                DropdownButtonFormField<ExternalApiProvider>(
                  key: ValueKey('provider-${_apiProvider.name}'),
                  initialValue: _apiProvider,
                  decoration: InputDecoration(
                    labelText: strings.t('apiProvider'),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: ExternalApiProvider.openAiCompatible,
                      child: Text('OpenAI-compatible'),
                    ),
                    DropdownMenuItem(
                      value: ExternalApiProvider.deepSeek,
                      child: Text(strings.t('deepSeekApi')),
                    ),
                    const DropdownMenuItem(
                      value: ExternalApiProvider.anthropic,
                      child: Text('Anthropic Messages API'),
                    ),
                  ],
                  onChanged: _onProviderChanged,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.t('apiBaseUrl'),
                    hintText: 'https://api.example.com/v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: strings.t('apiModel')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: !_showApiKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: strings.t('apiKey'),
                    suffixIcon: IconButton(
                      tooltip: strings.t(
                        _showApiKey ? 'hideApiKey' : 'showApiKey',
                      ),
                      onPressed: () =>
                          setState(() => _showApiKey = !_showApiKey),
                      icon: Icon(
                        _showApiKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _timeout,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: strings.t('apiTimeout'),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.shield_outlined,
              title: strings.t('privacy'),
              children: [
                TextField(
                  controller: _corporateTerms,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: strings.t('corporateTerms'),
                    hintText: 'bank.local, PaymentCore, project-secret',
                  ),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.bluetooth_searching,
              title: strings.t('device'),
              trailing: _ConnectionIndicator(status: controller.deviceStatus),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CodeKeyTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: CodeKeyTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.bluetooth_searching,
                        color: CodeKeyTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.t('deviceDiscoveryHint'),
                          style: const TextStyle(
                            color: CodeKeyTheme.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _setupKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: strings.t('setupKey')),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.scanning
                            ? null
                            : () => _scan(controller),
                        icon: controller.scanning
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.radar),
                        label: Text(
                          strings.t(controller.scanning ? 'scanning' : 'scan'),
                        ),
                      ),
                    ),
                    if (controller.deviceStatus.connectionState !=
                        CodeKeyConnectionState.disconnected) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: controller.disconnectDevice,
                        child: Text(strings.t('disconnect')),
                      ),
                    ],
                  ],
                ),
                if (_hasScanned &&
                    !controller.scanning &&
                    controller.discoveredDevices.isEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    strings.t('noDevices'),
                    style: const TextStyle(color: CodeKeyTheme.muted),
                  ),
                ],
                if (controller.discoveredDevices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...controller.discoveredDevices.map(
                    (device) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: CodeKeyTheme.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: CodeKeyTheme.border),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.memory_outlined),
                        title: Text(device.name),
                        subtitle: Text('${device.id} • RSSI ${device.rssi}'),
                        trailing: FilledButton(
                          onPressed: () => _connect(controller, device),
                          child: Text(strings.t('connect')),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (controller.deviceStatus.isReady)
              _SettingsSection(
                icon: Icons.usb_rounded,
                title: strings.t('usbIdentity'),
                children: [
                  _UsbWarning(text: strings.t('usbWarning')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _productPreset(_product.text),
                    decoration: InputDecoration(
                      labelText: strings.t('productPreset'),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'CodeKey Keyboard',
                        child: Text('CodeKey Keyboard'),
                      ),
                      const DropdownMenuItem(
                        value: 'Generic USB Keyboard',
                        child: Text('Generic USB Keyboard'),
                      ),
                      const DropdownMenuItem(
                        value: 'USB HID Keyboard',
                        child: Text('USB HID Keyboard'),
                      ),
                      DropdownMenuItem(
                        value: '__custom__',
                        child: Text(strings.t('custom')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null && value != '__custom__') {
                        _product.text = value;
                      }
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HexField(
                          controller: _vid,
                          label: strings.t('vid'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HexField(
                          controller: _pid,
                          label: strings.t('pid'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manufacturer,
                    decoration: InputDecoration(
                      labelText: strings.t('manufacturer'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _product,
                    decoration: InputDecoration(
                      labelText: strings.t('productName'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serial,
                    decoration: InputDecoration(
                      labelText: strings.t('serialNumber'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _applyUsb(context, controller),
                    icon: const Icon(Icons.restart_alt),
                    label: Text(strings.t('applyUsb')),
                  ),
                ],
              ),
            _SettingsSection(
              icon: Icons.bug_report_outlined,
              title: strings.t('diagnostics'),
              children: [
                Text(
                  strings.t('diagnosticsHint'),
                  style: const TextStyle(
                    color: CodeKeyTheme.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    onPressed: _sharingLogs
                        ? null
                        : () => _shareDiagnostics(buttonContext, controller),
                    icon: _sharingLogs
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_outlined),
                    label: Text(strings.t('exportLogs')),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _clearLogs(controller),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(strings.t('clearLogs')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  AppSettings _collect(AppSettings old) => old.copyWith(
    language: _language,
    os: _os,
    editor: _editor,
    keyboardLayouts: List<KeyboardLayoutOption>.unmodifiable(_keyboardLayouts),
    activeKeyboardLayoutId: _activeLayoutId,
    charactersPerSecond: _speed.round(),
    humanized: _humanized,
    apiProvider: _apiProvider,
    apiBaseUrl: _baseUrl.text.trim(),
    apiModel: _model.text.trim(),
    apiKey: _apiKey.text.trim(),
    apiTimeoutSeconds: (int.tryParse(_timeout.text) ?? 90)
        .clamp(10, 600)
        .toInt(),
    corporateTerms: _corporateTerms.text.trim(),
    setupKey: _setupKey.text.trim(),
    usbVid: _vid.text.trim().toUpperCase(),
    usbPid: _pid.text.trim().toUpperCase(),
    usbManufacturer: _manufacturer.text.trim(),
    usbProduct: _product.text.trim(),
    usbSerial: _serial.text.trim(),
  );

  Future<void> _save(
    BuildContext context,
    CodeKeyController controller,
  ) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final savedText = context.strings.t('saved');
    try {
      if (controller.deviceStatus.isReady) _validateUsb();
      await controller.updateSettings(_collect(controller.settings));
      if (!context.mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(savedText)));
    } on Object catch (error) {
      if (context.mounted) _showSettingsError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan(CodeKeyController controller) async {
    try {
      final devices = await controller.scanDevices();
      if (!mounted) return;
      setState(() => _hasScanned = true);
      final key = devices.isEmpty ? 'noDevices' : 'devicesFound';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.t(key, {'count': devices.length}),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _hasScanned = true);
        _showSettingsError(context, error);
      }
    }
  }

  Future<void> _connect(
    CodeKeyController controller,
    DiscoveredCodeKey device,
  ) async {
    try {
      final settings = _collect(controller.settings);
      await controller.updateSettings(settings);
      await controller.connectDevice(device, settings.setupKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.t('connected'))),
        );
      }
    } on Object catch (error) {
      if (mounted) _showSettingsError(context, error);
    }
  }

  Future<void> _applyUsb(
    BuildContext context,
    CodeKeyController controller,
  ) async {
    try {
      _validateUsb();
      await controller.updateSettings(_collect(controller.settings));
      await controller.applyUsbIdentity();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.t('deviceConfigSaved'))),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showSettingsError(context, error);
    }
  }

  Future<void> _shareDiagnostics(
    BuildContext buttonContext,
    CodeKeyController controller,
  ) async {
    setState(() => _sharingLogs = true);
    try {
      final file = await controller.exportDiagnostics();
      if (!mounted) return;
      final box = buttonContext.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          title: 'CodeKey diagnostics',
          subject: 'CodeKey diagnostics',
          text: context.strings.t('diagnosticsShareText'),
          files: [XFile(file.path, mimeType: 'application/x-ndjson')],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on Object catch (error) {
      if (mounted) _showSettingsError(context, error);
    } finally {
      if (mounted) setState(() => _sharingLogs = false);
    }
  }

  Future<void> _clearLogs(CodeKeyController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.strings.t('clearLogs')),
        content: Text(dialogContext.strings.t('clearLogsConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.strings.t('close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.strings.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.clearDiagnostics();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.t('logsCleared'))),
      );
    }
  }

  void _onProviderChanged(ExternalApiProvider? value) {
    if (value == null) return;
    setState(() {
      final previous = _apiProvider;
      _apiProvider = value;
      switch (value) {
        case ExternalApiProvider.deepSeek:
          _baseUrl.text = 'https://api.deepseek.com';
          if (_model.text.trim().isEmpty ||
              previous != ExternalApiProvider.deepSeek) {
            _model.text = 'deepseek-v4-flash';
          }
          break;
        case ExternalApiProvider.openAiCompatible:
          if (previous == ExternalApiProvider.deepSeek &&
              _baseUrl.text.contains('api.deepseek.com')) {
            _baseUrl.text = 'https://api.openai.com/v1';
            _model.clear();
          }
          break;
        case ExternalApiProvider.anthropic:
          if (previous == ExternalApiProvider.deepSeek &&
              _baseUrl.text.contains('api.deepseek.com')) {
            _baseUrl.text = 'https://api.anthropic.com/v1';
            _model.clear();
          }
          break;
      }
    });
  }

  Future<void> _addLayout() async {
    final name = TextEditingController();
    final code = TextEditingController();
    var baseProfile = KeyboardLayoutProfile.enUs;
    final result = await showDialog<KeyboardLayoutOption>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(dialogContext.strings.t('addLayout')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: dialogContext.strings.t('layoutName'),
                    hintText: 'Русская — Windows',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  maxLength: 10,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: dialogContext.strings.t('layoutCode'),
                    hintText: 'RU',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<KeyboardLayoutProfile>(
                  initialValue: baseProfile,
                  decoration: InputDecoration(
                    labelText: dialogContext.strings.t('baseLayout'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: KeyboardLayoutProfile.enUs,
                      child: Text('English — US'),
                    ),
                    DropdownMenuItem(
                      value: KeyboardLayoutProfile.enGb,
                      child: Text('English — UK'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => baseProfile = value ?? baseProfile,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.strings.t('close')),
            ),
            FilledButton(
              onPressed: () {
                final cleanName = name.text.trim();
                final cleanCode = code.text.trim().toUpperCase();
                if (cleanName.isEmpty || cleanCode.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  KeyboardLayoutOption(
                    id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
                    code: cleanCode,
                    name: cleanName,
                    baseProfile: baseProfile,
                  ),
                );
              },
              child: Text(dialogContext.strings.t('add')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    code.dispose();
    if (result == null || !mounted) return;
    if (_keyboardLayouts.any(
      (item) => item.code.toUpperCase() == result.code.toUpperCase(),
    )) {
      _showSettingsError(context, const FormatException('layout_code_exists'));
      return;
    }
    setState(() {
      _keyboardLayouts = [..._keyboardLayouts, result];
      _activeLayoutId = result.id;
    });
  }

  void _deleteLayout(KeyboardLayoutOption layout) {
    if (layout.builtIn || _keyboardLayouts.length <= 1) return;
    setState(() {
      _keyboardLayouts = _keyboardLayouts
          .where((item) => item.id != layout.id)
          .toList(growable: false);
      if (_activeLayoutId == layout.id) {
        _activeLayoutId = _keyboardLayouts.first.id;
      }
    });
  }

  void _validateUsb() {
    final hex = RegExp(r'^[0-9A-Fa-f]{4}$');
    if (!hex.hasMatch(_vid.text.trim()) || !hex.hasMatch(_pid.text.trim())) {
      throw const FormatException('invalid_vid_pid');
    }
    if (_vid.text.trim().toUpperCase() == '0000' ||
        _pid.text.trim().toUpperCase() == '0000') {
      throw const FormatException('zero_vid_pid');
    }
    if (_manufacturer.text.trim().isEmpty ||
        _product.text.trim().isEmpty ||
        _serial.text.trim().isEmpty) {
      throw const FormatException('empty_usb_fields');
    }
    if (_manufacturer.text.length > 31 ||
        _product.text.length > 31 ||
        _serial.text.length > 31) {
      throw const FormatException('usb_fields_too_long');
    }
  }

  String _productPreset(String value) {
    const known = {
      'CodeKey Keyboard',
      'Generic USB Keyboard',
      'USB HID Keyboard',
    };
    return known.contains(value) ? value : '__custom__';
  }

  String _baseLayoutLabel(KeyboardLayoutProfile profile) => switch (profile) {
    KeyboardLayoutProfile.enUs => 'USB map: English — US',
    KeyboardLayoutProfile.enGb => 'USB map: English — UK',
  };

  String _osLabel(WorkstationOs os) => switch (os) {
    WorkstationOs.windows => 'Windows',
    WorkstationOs.linux => 'Linux',
    WorkstationOs.macos => 'macOS',
  };

  String _editorLabel(
    EditorProfile editor,
    CodeKeyLocalizations strings,
  ) => switch (editor) {
    EditorProfile.generic => strings.t('genericEditor'),
    EditorProfile.vscode => 'Visual Studio Code',
    EditorProfile.jetBrains => 'JetBrains IDE',
    EditorProfile.visualStudio => 'Visual Studio',
    EditorProfile.androidStudio => 'Android Studio',
    EditorProfile.xcode => 'Xcode',
  };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CodeKeyTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CodeKeyTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CodeKeyTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: CodeKeyTheme.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.status});
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final ready = status.isReady;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (ready ? CodeKeyTheme.success : CodeKeyTheme.muted)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: ready ? CodeKeyTheme.success : CodeKeyTheme.muted,
          ),
          const SizedBox(width: 6),
          Text(
            context.strings.t(ready ? 'connected' : 'disconnected'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HexField extends StatelessWidget {
  const _HexField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 4,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f]')),
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}

class _UsbWarning extends StatelessWidget {
  const _UsbWarning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CodeKeyTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CodeKeyTheme.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: CodeKeyTheme.warning,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

void _showSettingsError(BuildContext context, Object error) {
  final code = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
  final translated = context.strings.t(code);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(translated == code ? code : translated),
      backgroundColor: CodeKeyTheme.danger,
    ),
  );
}
