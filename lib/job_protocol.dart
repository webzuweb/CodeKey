import 'dart:math';
import 'dart:typed_data';

import 'models.dart';

class HidUsage {
  static const enter = 0x28;
  static const escape = 0x29;
  static const backspace = 0x2A;
  static const tab = 0x2B;
  static const deleteForward = 0x4C;

  static int letter(String value) => 0x04 + value.toLowerCase().codeUnitAt(0) - 0x61;
}

class HidModifier {
  static const leftCtrl = 1 << 0;
  static const leftShift = 1 << 1;
  static const leftAlt = 1 << 2;
  static const leftGui = 1 << 3;
  static const rightCtrl = 1 << 4;
  static const rightShift = 1 << 5;
  static const rightAlt = 1 << 6;
  static const rightGui = 1 << 7;
}

class KeyStroke {
  const KeyStroke(this.modifiers, this.usage);
  final int modifiers;
  final int usage;
}

class UnsupportedCharactersException implements Exception {
  const UnsupportedCharactersException(this.characters);
  final Set<String> characters;
  @override
  String toString() => characters.join(' ');
}

class KeyboardLayoutEncoder {
  List<KeyStroke> encode(String text, KeyboardLayoutProfile layout) {
    final map = layout == KeyboardLayoutProfile.enGb ? _ukMap() : _usMap();
    final output = <KeyStroke>[];
    final unsupported = <String>{};
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      final stroke = map[char];
      if (stroke == null) {
        unsupported.add('U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} “$char”');
      } else {
        output.add(stroke);
      }
    }
    if (unsupported.isNotEmpty) throw UnsupportedCharactersException(unsupported);
    return output;
  }

  Map<String, KeyStroke> _usMap() {
    final map = <String, KeyStroke>{
      ' ': const KeyStroke(0, 0x2C),
      '\n': const KeyStroke(0, HidUsage.enter),
      '\t': const KeyStroke(0, HidUsage.tab),
    };
    for (var index = 0; index < 26; index++) {
      final lower = String.fromCharCode(0x61 + index);
      final upper = String.fromCharCode(0x41 + index);
      final usage = 0x04 + index;
      map[lower] = KeyStroke(0, usage);
      map[upper] = KeyStroke(HidModifier.leftShift, usage);
    }

    void pair(String normal, String shifted, int usage) {
      map[normal] = KeyStroke(0, usage);
      map[shifted] = KeyStroke(HidModifier.leftShift, usage);
    }

    pair('1', '!', 0x1E);
    pair('2', '@', 0x1F);
    pair('3', '#', 0x20);
    pair('4', r'$', 0x21);
    pair('5', '%', 0x22);
    pair('6', '^', 0x23);
    pair('7', '&', 0x24);
    pair('8', '*', 0x25);
    pair('9', '(', 0x26);
    pair('0', ')', 0x27);
    pair('-', '_', 0x2D);
    pair('=', '+', 0x2E);
    pair('[', '{', 0x2F);
    pair(']', '}', 0x30);
    pair('\\', '|', 0x31);
    pair(';', ':', 0x33);
    pair("'", '"', 0x34);
    pair('`', '~', 0x35);
    pair(',', '<', 0x36);
    pair('.', '>', 0x37);
    pair('/', '?', 0x38);
    return map;
  }

  Map<String, KeyStroke> _ukMap() {
    final map = _usMap();
    map['"'] = const KeyStroke(HidModifier.leftShift, 0x1F);
    map['@'] = const KeyStroke(HidModifier.leftShift, 0x34);
    map['#'] = const KeyStroke(0, 0x32);
    map['~'] = const KeyStroke(HidModifier.leftShift, 0x32);
    map['\\'] = const KeyStroke(0, 0x64);
    map['|'] = const KeyStroke(HidModifier.leftShift, 0x64);
    return map;
  }
}

class SemanticHotkeyMapper {
  List<_KeyboardAction> resolve(
    SemanticAction action,
    WorkstationOs os,
    EditorProfile editor,
  ) {
    final primary = os == WorkstationOs.macos
        ? HidModifier.leftGui
        : HidModifier.leftCtrl;
    final alt = os == WorkstationOs.macos
        ? HidModifier.leftAlt
        : HidModifier.leftAlt;

    _KeyboardAction chord(int modifiers, String letter, [int waitAfter = 80]) =>
        _KeyboardAction.chord(modifiers, HidUsage.letter(letter), waitAfter);

    switch (action) {
      case SemanticAction.save:
        return [chord(primary, 's')];
      case SemanticAction.saveAs:
        return [chord(primary | HidModifier.leftShift, 's')];
      case SemanticAction.newFile:
        return [chord(primary, 'n')];
      case SemanticAction.closeFile:
        return [chord(primary, 'w')];
      case SemanticAction.undo:
        return [chord(primary, 'z')];
      case SemanticAction.redo:
        return os == WorkstationOs.macos
            ? [chord(primary | HidModifier.leftShift, 'z')]
            : [chord(primary, 'y')];
      case SemanticAction.selectAll:
        return [chord(primary, 'a')];
      case SemanticAction.find:
        return [chord(primary, 'f')];
      case SemanticAction.commandPalette:
        if (editor == EditorProfile.vscode) {
          return [chord(primary | HidModifier.leftShift, 'p')];
        }
        return const [];
      case SemanticAction.formatDocument:
        return _formatDocument(os, editor, primary, alt);
      case SemanticAction.enter:
        return const [_KeyboardAction.tap(HidUsage.enter)];
      case SemanticAction.backspace:
        return const [_KeyboardAction.tap(HidUsage.backspace)];
      case SemanticAction.deleteForward:
        return const [_KeyboardAction.tap(HidUsage.deleteForward)];
      case SemanticAction.tab:
        return const [_KeyboardAction.tap(HidUsage.tab)];
      case SemanticAction.outdent:
        return const [_KeyboardAction.chord(HidModifier.leftShift, HidUsage.tab, 80)];
      case SemanticAction.escape:
        return const [_KeyboardAction.tap(HidUsage.escape)];
    }
  }

  List<_KeyboardAction> _formatDocument(
    WorkstationOs os,
    EditorProfile editor,
    int primary,
    int alt,
  ) {
    switch (editor) {
      case EditorProfile.vscode:
        return [
          _KeyboardAction.chord(
            HidModifier.leftShift | alt,
            HidUsage.letter('f'),
            120,
          ),
        ];
      case EditorProfile.jetBrains:
      case EditorProfile.androidStudio:
        return [
          _KeyboardAction.chord(
            os == WorkstationOs.macos
                ? HidModifier.leftAlt | HidModifier.leftGui
                : HidModifier.leftCtrl | HidModifier.leftAlt,
            HidUsage.letter('l'),
            120,
          ),
        ];
      case EditorProfile.visualStudio:
        if (os == WorkstationOs.macos) return const [];
        return [
          _KeyboardAction.chord(HidModifier.leftCtrl, HidUsage.letter('k'), 100),
          _KeyboardAction.chord(HidModifier.leftCtrl, HidUsage.letter('d'), 120),
        ];
      case EditorProfile.xcode:
        return [
          _KeyboardAction.chord(HidModifier.leftCtrl, HidUsage.letter('i'), 120),
        ];
      case EditorProfile.generic:
        return const [];
    }
  }
}

class _KeyboardAction {
  const _KeyboardAction.chord(this.modifiers, this.usage, this.waitAfterMs)
      : count = 1;
  const _KeyboardAction.tap(this.usage, {this.count = 1, this.waitAfterMs = 80})
      : modifiers = 0;

  final int modifiers;
  final int usage;
  final int count;
  final int waitAfterMs;
}

class CompiledJob {
  const CompiledJob({
    required this.id,
    required this.bytes,
    required this.crc32,
    required this.totalSteps,
  });

  final String id;
  final Uint8List bytes;
  final int crc32;
  final int totalSteps;
}

class JobCompiler {
  JobCompiler({
    KeyboardLayoutEncoder? encoder,
    SemanticHotkeyMapper? hotkeys,
  }) : _encoder = encoder ?? KeyboardLayoutEncoder(),
       _hotkeys = hotkeys ?? SemanticHotkeyMapper();

  static const _textAscii = 0x01;
  static const _chord = 0x02;
  static const _wait = 0x03;
  static const _keyTap = 0x04;
  static const _keyStream = 0x05;
  static const _releaseAll = 0xFE;
  static const _end = 0xFF;

  final KeyboardLayoutEncoder _encoder;
  final SemanticHotkeyMapper _hotkeys;

  CompiledJob compile({
    required String code,
    required AppSettings settings,
    List<SemanticAction> before = const [],
    List<SemanticAction> after = const [],
  }) {
    final writer = BytesBuilder(copy: false);
    var steps = 0;

    for (final action in before) {
      steps += _appendSemantic(writer, action, settings);
    }

    final strokes = _encoder.encode(code, settings.layout);
    const pairsPerRecord = 180;
    for (var offset = 0; offset < strokes.length; offset += pairsPerRecord) {
      final end = min(offset + pairsPerRecord, strokes.length);
      final payload = BytesBuilder(copy: false);
      for (var index = offset; index < end; index++) {
        payload.add([strokes[index].modifiers, strokes[index].usage]);
      }
      _record(writer, _keyStream, payload.takeBytes());
    }
    steps += strokes.length;

    if (after.isNotEmpty) _waitRecord(writer, 250);
    for (final action in after) {
      steps += _appendSemantic(writer, action, settings);
    }
    _record(writer, _releaseAll, Uint8List(0));
    _record(writer, _end, Uint8List(0));

    final bytes = writer.takeBytes();
    return CompiledJob(
      id: _randomId(),
      bytes: bytes,
      crc32: Crc32.compute(bytes),
      totalSteps: steps,
    );
  }

  int _appendSemantic(
    BytesBuilder writer,
    SemanticAction action,
    AppSettings settings,
  ) {
    final commands = _hotkeys.resolve(action, settings.os, settings.editor);
    for (final command in commands) {
      if (command.modifiers == 0) {
        final payload = ByteData(3)
          ..setUint8(0, command.usage)
          ..setUint16(1, command.count, Endian.little);
        _record(writer, _keyTap, payload.buffer.asUint8List());
      } else {
        _record(writer, _chord, Uint8List.fromList([
          command.modifiers,
          command.usage,
        ]));
      }
      if (command.waitAfterMs > 0) _waitRecord(writer, command.waitAfterMs);
    }
    return commands.fold(0, (sum, command) => sum + command.count);
  }

  void _waitRecord(BytesBuilder writer, int milliseconds) {
    final payload = ByteData(4)..setUint32(0, milliseconds, Endian.little);
    _record(writer, _wait, payload.buffer.asUint8List());
  }

  void _record(BytesBuilder writer, int type, Uint8List payload) {
    if (payload.length > 0xFFFF) throw StateError('Record is too large');
    final header = ByteData(3)
      ..setUint8(0, type)
      ..setUint16(1, payload.length, Endian.little);
    writer.add(header.buffer.asUint8List());
    writer.add(payload);
  }

  String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

class Crc32 {
  static int compute(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }
}
