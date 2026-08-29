import 'package:codekey_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom keyboard layouts survive persistence', () {
    const custom = KeyboardLayoutOption(
      id: 'ru-windows',
      code: 'RU',
      name: 'Русская — Windows',
      baseProfile: KeyboardLayoutProfile.enUs,
    );
    const settings = AppSettings(
      keyboardLayouts: [...defaultKeyboardLayouts, custom],
      activeKeyboardLayoutId: 'ru-windows',
    );

    final restored = AppSettings.fromPersistedJson(
      settings.toPersistedJson(),
      apiKey: 'api-key',
      setupKey: 'setup-key',
    );

    expect(restored.keyboardLayouts, hasLength(3));
    expect(restored.activeKeyboardLayout.id, 'ru-windows');
    expect(restored.activeKeyboardLayout.code, 'RU');
    expect(restored.apiKey, 'api-key');
    expect(restored.setupKey, 'setup-key');
  });

  test('legacy layout setting migrates to the new list', () {
    final restored = AppSettings.fromPersistedJson(
      <String, Object?>{'layout': 'enGb'},
      apiKey: '',
      setupKey: '',
    );

    expect(restored.activeKeyboardLayoutId, 'en-gb');
    expect(restored.layout, KeyboardLayoutProfile.enGb);
  });

  test('copyWith falls back when active layout was removed', () {
    const settings = AppSettings(
      activeKeyboardLayoutId: 'en-gb',
    );
    final updated = settings.copyWith(
      keyboardLayouts: const [defaultKeyboardLayouts.first],
    );

    expect(updated.activeKeyboardLayoutId, 'en-us');
  });
}
