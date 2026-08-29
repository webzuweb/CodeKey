import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'controller_scope.dart';
import 'job_protocol.dart';
import 'localization.dart';
import 'models.dart';
import 'settings_page.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _promptController = TextEditingController();
  bool _autoScanStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = CodeKeyScope.read(context);
    if (!_autoScanStarted &&
        controller.initialized &&
        controller.settings.bleDeviceId.isEmpty &&
        !controller.scanning) {
      _autoScanStarted = true;
      unawaited(controller.scanDevices().then<void>((_) {}, onError: (_) {}));
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = CodeKeyScope.of(context);
    final strings = context.strings;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF111A38), CodeKeyTheme.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(controller: controller),
              Expanded(
                child: controller.initialized
                    ? _ConversationBody(controller: controller)
                    : const Center(child: CircularProgressIndicator()),
              ),
              _Composer(
                controller: controller,
                textController: _promptController,
                onSend: () => _send(context, controller),
                onEditScreenshot: (item) => _editOcr(context, controller, item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context, CodeKeyController controller) async {
    FocusScope.of(context).unfocus();
    try {
      final prepared = controller.prepareSubmission(_promptController.text);
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PrivacyReviewSheet(submission: prepared),
      );
      if (confirmed != true || !context.mounted) return;
      await controller.submit(prepared, _promptController.text);
      if (context.mounted) _promptController.clear();
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _editOcr(
    BuildContext context,
    CodeKeyController controller,
    ScreenshotItem item,
  ) async {
    final editor = TextEditingController(text: item.ocrText);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: _SheetSurface(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.document_scanner_outlined, color: CodeKeyTheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(strings.t('editOcr'), style: Theme.of(sheetContext).textTheme.titleLarge),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: editor,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.45),
                      decoration: const InputDecoration(contentPadding: EdgeInsets.all(16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, 'delete'),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(strings.t('delete')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, 'save'),
                          icon: const Icon(Icons.check),
                          label: Text(strings.t('save')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (action == 'save') controller.editOcr(item.id, editor.text);
    if (action == 'delete') await controller.removeScreenshot(item.id);
    editor.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final CodeKeyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final connected = controller.deviceStatus.isReady;
    final connecting = controller.deviceStatus.connectionState == CodeKeyConnectionState.connecting;
    final statusText = connected
        ? strings.t('connected')
        : connecting
            ? strings.t('connecting')
            : strings.t('disconnected');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.t('appName'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 27),
            ),
          ),
          _HeaderChip(
            onTap: () => _openSettings(context),
            icon: Icons.usb_rounded,
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: connected ? CodeKeyTheme.success : CodeKeyTheme.muted,
                shape: BoxShape.circle,
              ),
            ),
            label: controller.settings.bleDeviceName.isEmpty
                ? statusText
                : controller.settings.bleDeviceName,
          ),
          const SizedBox(width: 8),
          _HeaderChip(
            onTap: () => _openSettings(context),
            icon: Icons.keyboard_alt_outlined,
            label: controller.settings.layout == KeyboardLayoutProfile.enUs ? 'EN-US' : 'EN-GB',
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: strings.t('settings'),
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.onTap,
    required this.icon,
    required this.label,
    this.leading,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 145),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: CodeKeyTheme.surfaceHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CodeKeyTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 7)],
            Icon(icon, size: 18, color: CodeKeyTheme.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationBody extends StatelessWidget {
  const _ConversationBody({required this.controller});
  final CodeKeyController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.response == null) _EmptyAssistantCard(controller: controller),
          if (controller.response != null) ...[
            if (controller.lastUserRequest.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: CodeKeyTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: CodeKeyTheme.border),
                  ),
                  child: Text(
                    controller.lastUserRequest,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            _ResponseCard(controller: controller, response: controller.response!),
          ],
          if (controller.processingApi)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _EmptyAssistantCard extends StatelessWidget {
  const _EmptyAssistantCard({required this.controller});
  final CodeKeyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CodeKeyTheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: CodeKeyTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: CodeKeyTheme.actionGradient,
            ),
            child: const Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.t('appName'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 7),
                Text(
                  strings.t('promptHint'),
                  style: const TextStyle(color: CodeKeyTheme.muted),
                ),
                if (!controller.deviceStatus.isReady) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                    ),
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(
                      controller.discoveredDevices.isEmpty
                          ? strings.t('connect')
                          : '${strings.t('connect')}: ${controller.discoveredDevices.first.name}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({required this.controller, required this.response});
  final CodeKeyController controller;
  final LlmCodingResponse response;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: BoxDecoration(
        color: CodeKeyTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: CodeKeyTheme.border),
        boxShadow: const [
          BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: CodeKeyTheme.actionGradient,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(strings.t('responseFromLlm'), style: Theme.of(context).textTheme.titleLarge),
                ),
                const Icon(Icons.check_circle_outline, color: CodeKeyTheme.success),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.task_alt, color: CodeKeyTheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        strings.t('whatChanged'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFB59AFF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(response.explanation, style: const TextStyle(fontSize: 16, height: 1.5)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.code_rounded, color: CodeKeyTheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(strings.t('codeToInsert'), style: Theme.of(context).textTheme.titleMedium),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: response.code));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('copied'))));
                        }
                      },
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: Text(strings.t('copy')),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 460),
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B13),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: CodeKeyTheme.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      response.code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFFE2E8F8),
                      ),
                    ),
                  ),
                ),
                if (response.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded, color: CodeKeyTheme.warning),
                    title: Text(strings.t('technicalWarnings')),
                    children: response.warnings
                        .map((warning) => ListTile(
                              dense: true,
                              leading: const Text('•'),
                              title: Text(warning),
                            ))
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: CodeKeyTheme.actionGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Color(0x557657FF), blurRadius: 22, offset: Offset(0, 8)),
                    ],
                  ),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _PrintSheet(controller: controller, response: response),
                    ),
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: Text(strings.t('print'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, size: 15, color: CodeKeyTheme.muted),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        strings.t('printHint'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CodeKeyTheme.muted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.textController,
    required this.onSend,
    required this.onEditScreenshot,
  });

  final CodeKeyController controller;
  final TextEditingController textController;
  final VoidCallback onSend;
  final ValueChanged<ScreenshotItem> onEditScreenshot;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final showScreenshots = controller.response == null && controller.screenshots.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CodeKeyTheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: CodeKeyTheme.border),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showScreenshots) ...[
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: controller.screenshots.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == controller.screenshots.length) {
                    return _AddScreenshotTile(onTap: controller.addScreenshot);
                  }
                  final item = controller.screenshots[index];
                  return _ScreenshotTile(
                    index: index + 1,
                    item: item,
                    onTap: () => onEditScreenshot(item),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                tooltip: strings.t('addPhoto'),
                onPressed: controller.processingApi ? null : () async {
                  try {
                    await controller.addScreenshot();
                  } on Object catch (error) {
                    if (context.mounted) _showError(context, error);
                  }
                },
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: strings.t('promptHint'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              DecoratedBox(
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: CodeKeyTheme.actionGradient),
                child: IconButton(
                  tooltip: strings.t('send'),
                  onPressed: controller.processingApi ? null : onSend,
                  icon: controller.processingApi
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenshotTile extends StatelessWidget {
  const _ScreenshotTile({required this.index, required this.item, required this.onTap});
  final int index;
  final ScreenshotItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final label = switch (item.state) {
      OcrState.queued => strings.t('ocrQueued'),
      OcrState.processing => '${strings.t('ocr')} ${(item.progress * 100).round()}%',
      OcrState.done => strings.t('ocrDone'),
      OcrState.failed => strings.t('ocrFailed'),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          color: CodeKeyTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.state == OcrState.done ? CodeKeyTheme.primary : CodeKeyTheme.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: item.path.isNotEmpty
                  ? Image.file(File(item.path), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
                  : const SizedBox(),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, CodeKeyTheme.background.withValues(alpha: 0.96)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              left: 7,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: CodeKeyTheme.primary,
                child: Text('$index', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: item.state == OcrState.processing ? item.progress : (item.state == OcrState.done ? 1 : 0),
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddScreenshotTile extends StatelessWidget {
  const _AddScreenshotTile({required this.onTap});
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        try {
          await onTap();
        } on Object catch (error) {
          if (context.mounted) _showError(context, error);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CodeKeyTheme.border, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: CodeKeyTheme.muted),
            const SizedBox(height: 7),
            Text(
              context.strings.t('addPhoto'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: CodeKeyTheme.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyReviewSheet extends StatefulWidget {
  const _PrivacyReviewSheet({required this.submission});
  final PreparedSubmission submission;

  @override
  State<_PrivacyReviewSheet> createState() => _PrivacyReviewSheetState();
}

class _PrivacyReviewSheetState extends State<_PrivacyReviewSheet> {
  bool authorized = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final findings = widget.submission.report.findings;
    return _SheetSurface(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: CodeKeyTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(strings.t('privacyCheck'), style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 12),
              if (findings.isEmpty)
                _Notice(text: strings.t('noFindings'), color: CodeKeyTheme.warning)
              else ...[
                Text(strings.t('findings', {'count': findings.length})),
                const SizedBox(height: 10),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    itemCount: findings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) {
                      final finding = findings[index];
                      return Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: CodeKeyTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _severityColor(finding.severity).withValues(alpha: 0.65)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 18, color: _severityColor(finding.severity)),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text('${finding.type}: ${finding.maskedPreview}', overflow: TextOverflow.ellipsis),
                            ),
                            Text(finding.placeholder, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(strings.t('maskedPayload'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 7),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B13),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CodeKeyTheme.border),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(strings.t('systemInstruction'), style: const TextStyle(color: CodeKeyTheme.primary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SelectableText(widget.submission.systemPrompt, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                      const SizedBox(height: 18),
                      Text(strings.t('userPayload'), style: const TextStyle(color: CodeKeyTheme.primary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SelectableText(widget.submission.userMessage, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: authorized,
                onChanged: (value) => setState(() => authorized = value ?? false),
                title: Text(strings.t('rightsConfirm')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(strings.t('backToEdit')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: authorized ? () => Navigator.pop(context, true) : null,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(strings.t('sendMasked')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(DlpSeverity severity) => switch (severity) {
    DlpSeverity.critical => CodeKeyTheme.danger,
    DlpSeverity.high => CodeKeyTheme.warning,
    DlpSeverity.medium => CodeKeyTheme.primary,
    DlpSeverity.low => CodeKeyTheme.muted,
  };
}

class _PrintSheet extends StatefulWidget {
  const _PrintSheet({required this.controller, required this.response});
  final CodeKeyController controller;
  final LlmCodingResponse response;

  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<_PrintSheet> {
  bool cursorReady = false;
  bool saveAfter = true;
  bool formatAfter = false;
  bool starting = false;
  int countdown = 0;
  String? localError;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final status = widget.controller.deviceStatus;
        final running = status.jobState == 'running' || status.jobState == 'paused';
        final completed = status.jobState == 'completed';
        return _SheetSurface(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: CodeKeyTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(strings.t('cursorPlacement'), style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(onPressed: running ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Notice(text: widget.response.placement, color: CodeKeyTheme.primary),
                  const SizedBox(height: 10),
                  Text('${strings.t('operation')}: ${_operationText(strings, widget.response.operation)}',
                      style: const TextStyle(color: CodeKeyTheme.muted)),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: cursorReady,
                    onChanged: running ? null : (value) => setState(() => cursorReady = value ?? false),
                    title: Text(strings.t('cursorReady')),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: saveAfter,
                    onChanged: running ? null : (value) => setState(() => saveAfter = value),
                    title: Text(strings.t('saveAfter')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: formatAfter,
                    onChanged: running ? null : (value) => setState(() => formatAfter = value),
                    title: Text(strings.t('formatAfter')),
                    subtitle: Text(widget.controller.settings.editor.name),
                  ),
                  if (!status.isReady && !running) ...[
                    const SizedBox(height: 8),
                    _Notice(text: strings.t('deviceRequired'), color: CodeKeyTheme.warning),
                  ],
                  if (localError != null) ...[
                    const SizedBox(height: 8),
                    _Notice(text: localError!, color: CodeKeyTheme.danger),
                  ],
                  if (running || completed) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: completed ? 1 : status.progress, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                    const SizedBox(height: 8),
                    Text(
                      completed
                          ? strings.t('completed')
                          : strings.t('printing', {'done': status.completedSteps, 'total': status.totalSteps}),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (!completed)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: status.jobState == 'paused'
                                  ? widget.controller.resumePrint
                                  : widget.controller.pausePrint,
                              icon: Icon(status.jobState == 'paused' ? Icons.play_arrow : Icons.pause),
                              label: Text(status.jobState == 'paused' ? strings.t('resume') : strings.t('pause')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: CodeKeyTheme.danger),
                              onPressed: widget.controller.stopPrint,
                              icon: const Icon(Icons.stop_rounded),
                              label: Text(strings.t('stop')),
                            ),
                          ),
                        ],
                      ),
                  ] else ...[
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: CodeKeyTheme.actionGradient, borderRadius: BorderRadius.circular(18)),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: cursorReady && status.isReady && !starting ? _start : null,
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: Text(
                          countdown > 0 ? '$countdown' : strings.t('startPrinting'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _start() async {
    setState(() {
      starting = true;
      localError = null;
      countdown = 3;
    });
    try {
      final job = widget.controller.compilePrintJob(saveAfter: saveAfter, formatAfter: formatAfter);
      for (var value = 3; value > 0; value--) {
        if (!mounted) return;
        setState(() => countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => countdown = 0);
      await widget.controller.startPrint(job);
    } on UnsupportedCharactersException catch (error) {
      if (mounted) {
        setState(() => localError = context.strings.t('asciiError', {'chars': error.characters.take(8).join(', ')}));
      }
    } on Object catch (error) {
      if (mounted) setState(() => localError = error.toString());
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: const BoxDecoration(
        color: CodeKeyTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: CodeKeyTheme.border)),
      ),
      child: child,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: const TextStyle(height: 1.45)),
    );
  }
}

String _operationText(CodeKeyLocalizations strings, CodeOperation operation) => switch (operation) {
  CodeOperation.insertAtCursor => strings.t('operationInsert'),
  CodeOperation.replaceSelection => strings.t('operationReplaceSelection'),
  CodeOperation.replaceFile => strings.t('operationReplaceFile'),
  CodeOperation.none => strings.t('operationNone'),
};

void _showError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: CodeKeyTheme.danger),
  );
}
