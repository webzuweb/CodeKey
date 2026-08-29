import 'package:codekey_app/job_protocol.dart';
import 'package:codekey_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRC32 matches the standard check vector', () {
    expect(Crc32.compute('123456789'.codeUnits), 0xCBF43926);
  });

  test('US layout encodes programming punctuation', () {
    final strokes = KeyboardLayoutEncoder().encode('aA{}[]:@\n', KeyboardLayoutProfile.enUs);
    expect(strokes, hasLength(9));
    expect(strokes.first.usage, 0x04);
    expect(strokes[1].modifiers, HidModifier.leftShift);
    expect(strokes.last.usage, HidUsage.enter);
  });

  test('job separates code from semantic save action', () {
    const settings = AppSettings();
    final job = JobCompiler().compile(
      code: 'const marker = "<CTRL+S>";\n',
      settings: settings,
      after: const [SemanticAction.save],
    );
    expect(job.bytes, isNotEmpty);
    expect(job.totalSteps, greaterThan(20));
    expect(job.crc32, isNot(0));
  });
}
