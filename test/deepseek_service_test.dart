import 'dart:convert';

import 'package:codekey_app/llm_service.dart';
import 'package:codekey_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('DeepSeek request uses its endpoint and strict JSON mode', () async {
    late http.Request captured;
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      captured = request;
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'schema_version': 1,
                  'explanation': 'Исправлена проверка null.',
                  'placement': 'Выделите функцию целиком.',
                  'operation': 'replace_selection',
                  'code': 'return value ?? 0;',
                  'warnings': <String>[],
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = LlmService(client: client);
    const settings = AppSettings(
      apiProvider: ExternalApiProvider.deepSeek,
      apiBaseUrl: 'https://api.deepseek.com',
      apiModel: 'deepseek-v4-flash',
      apiKey: 'test-key',
    );

    final result = await service.complete(
      settings: settings,
      request: 'Исправь функцию',
      code: 'return value;',
    );

    expect(captured.url.toString(), 'https://api.deepseek.com/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer test-key');
    expect(requestBody['model'], 'deepseek-v4-flash');
    expect(requestBody['thinking'], {'type': 'disabled'});
    expect(requestBody['response_format'], {'type': 'json_object'});
    expect(jsonEncode(requestBody), isNot(contains('windows')));
    expect(jsonEncode(requestBody), isNot(contains('vscode')));
    expect(result.operation, CodeOperation.replaceSelection);
    service.dispose();
  });
}
