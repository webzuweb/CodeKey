import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  late InterfaceLanguage _language;
  late WorkstationOs _os;
  late EditorProfile _editor;
  late KeyboardLayoutProfile _layout;
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
    _layout = settings.layout;
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
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                  initialValue: _language,
                  decoration: InputDecoration(labelText: strings.t('interfaceLanguage')),
                  items: const [
                    DropdownMenuItem(value: InterfaceLanguage.ru, child: Text('Русский')),
                    DropdownMenuItem(value: InterfaceLanguage.en, child: Text('English')),
                    DropdownMenuItem(value: InterfaceLanguage.es, child: Text('Español')),
                    DropdownMenuItem(value: InterfaceLanguage.zh, child: Text('简体中文')),
                  ],
                  onChanged: (value) => setState(() => _language = value ?? _language),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.computer_outlined,
              title: strings.t('workstation'),
              children: [
                DropdownButtonFormField<WorkstationOs>(
                  initialValue: _os,
                  decoration: InputDecoration(labelText: strings.t('operatingSystem')),
                  items: WorkstationOs.values
                      .map((value) => DropdownMenuItem(value: value, child: Text(_osLabel(value))))
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _os = value ?? _os),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EditorProfile>(
                  initialValue: _editor,
                  decoration: InputDecoration(labelText: strings.t('editor')),
                  items: EditorProfile.values
                      .map((value) => DropdownMenuItem(value: value, child: Text(_editorLabel(value, strings))))
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _editor = value ?? _editor),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<KeyboardLayoutProfile>(
                  initialValue: _layout,
                  decoration: InputDecoration(labelText: strings.t('keyboardLayout')),
                  items: const [
                    DropdownMenuItem(value: KeyboardLayoutProfile.enUs, child: Text('English — US (EN-US)')),
                    DropdownMenuItem(value: KeyboardLayoutProfile.enGb, child: Text('English — UK (EN-GB)')),
                  ],
                  onChanged: (value) => setState(() => _layout = value ?? _layout),
                ),
              ],
            ),
            _SettingsSection(
              icon: Icons.keyboard_alt_outlined,
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
                  initialValue: _apiProvider,
                  decoration: InputDecoration(labelText: strings.t('apiProvider')),
                  items: const [
                    DropdownMenuItem(
                      value: ExternalApiProvider.openAiCompatible,
                      child: Text('OpenAI-compatible'),
                    ),
                    DropdownMenuItem(
                      value: ExternalApiProvider.anthropic,
                      child: Text('Anthropic Messages API'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _apiProvider = value ?? _apiProvider),
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
                      tooltip: strings.t(_showApiKey ? 'hideApiKey' : 'showApiKey'),
                      onPressed: () => setState(() => _showApiKey = !_showApiKey),
                      icon: Icon(_showApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _timeout,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: strings.t('apiTimeout')),
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
                      const Icon(Icons.bluetooth_searching, color: CodeKeyTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.t('deviceDiscoveryHint'),
                          style: const TextStyle(color: CodeKeyTheme.muted, height: 1.4),
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
                        onPressed: controller.scanning ? null : () => _scan(controller),
                        icon: controller.scanning
                            ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.radar),
                        label: Text(strings.t(controller.scanning ? 'scanning' : 'scan')),
                      ),
                    ),
                    if (controller.deviceStatus.connectionState != CodeKeyConnectionState.disconnected) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: controller.disconnectDevice,
                        child: Text(strings.t('disconnect')),
                      ),
                    ],
                  ],
                ),
                if (!controller.scanning && controller.discoveredDevices.isEmpty) ...[
                  const SizedBox(height: 10),
                  Text(strings.t('noDevices'), style: const TextStyle(color: CodeKeyTheme.muted)),
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
            _SettingsSection(
              icon: Icons.usb_rounded,
              title: strings.t('usbIdentity'),
              children: [
                _UsbWarning(text: strings.t('usbWarning')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _productPreset(_product.text),
                  decoration: InputDecoration(labelText: strings.t('productPreset')),
                  items: [
                    const DropdownMenuItem(value: 'CodeKey Keyboard', child: Text('CodeKey Keyboard')),
                    const DropdownMenuItem(value: 'Generic USB Keyboard', child: Text('Generic USB Keyboard')),
                    const DropdownMenuItem(value: 'USB HID Keyboard', child: Text('USB HID Keyboard')),
                    DropdownMenuItem(value: '__custom__', child: Text(strings.t('custom'))),
                  ],
                  onChanged: (value) {
                    if (value != null && value != '__custom__') _product.text = value;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _HexField(controller: _vid, label: strings.t('vid'))),
                    const SizedBox(width: 12),
                    Expanded(child: _HexField(controller: _pid, label: strings.t('pid'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _manufacturer, decoration: InputDecoration(labelText: strings.t('manufacturer'))),
                const SizedBox(height: 12),
                TextField(controller: _product, decoration: InputDecoration(labelText: strings.t('productName'))),
                const SizedBox(height: 12),
                TextField(controller: _serial, decoration: InputDecoration(labelText: strings.t('serialNumber'))),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: controller.deviceStatus.isReady ? () => _applyUsb(context, controller) : null,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(strings.t('applyUsb')),
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
    layout: _layout,
    charactersPerSecond: _speed.round(),
    humanized: _humanized,
    apiProvider: _apiProvider,
    apiBaseUrl: _baseUrl.text.trim(),
    apiModel: _model.text.trim(),
    apiKey: _apiKey.text.trim(),
    apiTimeoutSeconds: (int.tryParse(_timeout.text) ?? 90).clamp(10, 600).toInt(),
    corporateTerms: _corporateTerms.text.trim(),
    setupKey: _setupKey.text.trim(),
    usbVid: _vid.text.trim().toUpperCase(),
    usbPid: _pid.text.trim().toUpperCase(),
    usbManufacturer: _manufacturer.text.trim(),
    usbProduct: _product.text.trim(),
    usbSerial: _serial.text.trim(),
  );

  Future<void> _save(BuildContext context, CodeKeyController controller) async {
    setState(() => _saving = true);
    try {
      _validateUsb();
      await controller.updateSettings(_collect(controller.settings));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.strings.t('saved'))));
      }
    } on Object catch (error) {
      if (context.mounted) _showSettingsError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan(CodeKeyController controller) async {
    try {
      await controller.scanDevices();
    } on Object catch (error) {
      if (mounted) _showSettingsError(context, error);
    }
  }

  Future<void> _connect(CodeKeyController controller, DiscoveredCodeKey device) async {
    try {
      final settings = _collect(controller.settings);
      await controller.updateSettings(settings);
      await controller.connectDevice(device, settings.setupKey);
    } on Object catch (error) {
      if (mounted) _showSettingsError(context, error);
    }
  }

  Future<void> _applyUsb(BuildContext context, CodeKeyController controller) async {
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

  void _validateUsb() {
    final hex = RegExp(r'^[0-9A-Fa-f]{4}$');
    if (!hex.hasMatch(_vid.text.trim()) || !hex.hasMatch(_pid.text.trim())) {
      throw const FormatException('VID and PID must contain exactly four hexadecimal characters.');
    }
    if (_vid.text.trim().toUpperCase() == '0000' ||
        _pid.text.trim().toUpperCase() == '0000') {
      throw const FormatException('VID and PID must be non-zero.');
    }
    if (_manufacturer.text.trim().isEmpty || _product.text.trim().isEmpty || _serial.text.trim().isEmpty) {
      throw const FormatException('USB text fields must not be empty.');
    }
    if (_manufacturer.text.length > 31 || _product.text.length > 31 || _serial.text.length > 31) {
      throw const FormatException('USB text fields are limited to 31 characters.');
    }
  }

  String _productPreset(String value) {
    const known = {'CodeKey Keyboard', 'Generic USB Keyboard', 'USB HID Keyboard'};
    return known.contains(value) ? value : '__custom__';
  }

  String _osLabel(WorkstationOs os) => switch (os) {
    WorkstationOs.windows => 'Windows',
    WorkstationOs.linux => 'Linux',
    WorkstationOs.macos => 'macOS',
  };

  String _editorLabel(EditorProfile editor, CodeKeyLocalizations strings) => switch (editor) {
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
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
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
        color: (ready ? CodeKeyTheme.success : CodeKeyTheme.muted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: ready ? CodeKeyTheme.success : CodeKeyTheme.muted),
          const SizedBox(width: 6),
          Text(context.strings.t(ready ? 'connected' : 'disconnected'), style: const TextStyle(fontSize: 12)),
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
        border: Border.all(color: CodeKeyTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: CodeKeyTheme.warning, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}

void _showSettingsError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString()), backgroundColor: CodeKeyTheme.danger),
  );
}
