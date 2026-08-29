import 'package:codekey_app/llm_service.dart';
import 'package:codekey_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict JSON response is parsed', () {
    final response = LlmService().parseResponse('''
      {
        "schema_version": 1,
        "explanation": "Fixed null handling.",
        "placement": "Select the whole function.",
        "operation": "replace_selection",
        "code": "return value ?? 0;",
        "warnings": []
      }
    ''');
    expect(response.operation, CodeOperation.replaceSelection);
    expect(response.code, contains('??'));
  });

  test('unknown JSON fields are rejected', () {
    expect(
      () => LlmService().parseResponse('''
        {"schema_version":1,"explanation":"x","placement":"y","operation":"none","code":"","warnings":[],"hotkey":"CTRL+S"}
      '''),
      throwsA(isA<LlmException>()),
    );
  });
}
