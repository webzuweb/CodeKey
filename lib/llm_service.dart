import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class LlmService {
  LlmService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const systemPrompt = '''You are a programming assistant.

You receive exactly two user-provided values: a natural-language request and OCR-recognized source code. Infer the programming language from the code. Do not ask for the operating system, code editor, keyboard layout, device identity, or programming-language metadata.

Return exactly one valid JSON object. Do not use Markdown fences. Do not add any text before or after JSON. The explanation and cursor-placement instruction must use the same natural language as the user's request.

Required schema:
{
  "schema_version": 1,
  "explanation": "What was changed and why, written for the user",
  "placement": "Where the user must place the cursor or which block must be selected",
  "operation": "insert_at_cursor | replace_selection | replace_file | none",
  "code": "Exact code text to type, with no explanation and no Markdown fences",
  "warnings": ["Optional warnings"]
}

Never put keyboard commands, hotkeys, shell commands for automation, or markers such as <CTRL+S> outside the literal code requested by the user. The mobile app independently decides all keyboard actions.''';

  String buildUserMessage({required String request, required String code}) =>
      'USER REQUEST:\n$request\n\nOCR SOURCE CODE:\n$code';

  Future<LlmCodingResponse> complete({
    required AppSettings settings,
    required String request,
    required String code,
  }) async {
    _validateSettings(settings);
    return switch (settings.apiProvider) {
      ExternalApiProvider.openAiCompatible => _completeOpenAiCompatible(
          settings: settings,
          request: request,
          code: code,
        ),
      ExternalApiProvider.anthropic => _completeAnthropic(
          settings: settings,
          request: request,
          code: code,
        ),
    };
  }

  Future<LlmCodingResponse> _completeOpenAiCompatible({
    required AppSettings settings,
    required String request,
    required String code,
  }) async {
    final endpoint = _chatCompletionsUri(settings.apiBaseUrl);
    final body = <String, Object?>{
      'model': settings.apiModel.trim(),
      'temperature': 0.1,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': buildUserMessage(request: request, code: code),
        },
      ],
      'response_format': {'type': 'json_object'},
    };

    var response = await _postOpenAi(endpoint, settings, body);
    if (response.statusCode == 400) {
      final retryBody = Map<String, Object?>.from(body)..remove('response_format');
      response = await _postOpenAi(endpoint, settings, retryBody);
    }
    _requireSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmException('invalid_api_envelope');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const LlmException('missing_api_choices');
    }
    final first = Map<String, dynamic>.from(choices.first as Map);
    final message = first['message'];
    if (message is! Map) throw const LlmException('missing_api_message');
    return parseResponse(_contentToString(message['content']));
  }

  Future<LlmCodingResponse> _completeAnthropic({
    required AppSettings settings,
    required String request,
    required String code,
  }) async {
    final endpoint = _anthropicMessagesUri(settings.apiBaseUrl);
    final response = await _postAnthropic(endpoint, settings, {
      'model': settings.apiModel.trim(),
      'max_tokens': 8192,
      'temperature': 0.1,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': buildUserMessage(request: request, code: code),
        },
      ],
    });
    _requireSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmException('invalid_api_envelope');
    }
    final content = decoded['content'];
    if (content is! List) throw const LlmException('missing_api_message');
    final text = content
        .whereType<Map>()
        .where((item) => item['type'] == 'text')
        .map((item) => item['text'])
        .whereType<String>()
        .join();
    if (text.trim().isEmpty) throw const LlmException('missing_api_message');
    return parseResponse(text);
  }

  Future<http.Response> _postOpenAi(
    Uri endpoint,
    AppSettings settings,
    Map<String, Object?> body,
  ) => _client
      .post(
        endpoint,
        headers: {
          'Authorization': 'Bearer ${settings.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_timeout(settings));

  Future<http.Response> _postAnthropic(
    Uri endpoint,
    AppSettings settings,
    Map<String, Object?> body,
  ) => _client
      .post(
        endpoint,
        headers: {
          'x-api-key': settings.apiKey.trim(),
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_timeout(settings));

  Duration _timeout(AppSettings settings) =>
      Duration(seconds: settings.apiTimeoutSeconds.clamp(10, 600).toInt());

  void _validateSettings(AppSettings settings) {
    if (settings.apiBaseUrl.trim().isEmpty ||
        settings.apiModel.trim().isEmpty ||
        settings.apiKey.trim().isEmpty) {
      throw const LlmException('api_not_configured');
    }
  }

  void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException(
        'api_http_${response.statusCode}: ${_safeBody(response.body)}',
      );
    }
  }

  LlmCodingResponse parseResponse(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false),
        '',
      );
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmException('llm_response_is_not_object');
    }
    const allowed = {
      'schema_version',
      'explanation',
      'placement',
      'operation',
      'code',
      'warnings',
    };
    final unknown = decoded.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw LlmException('unknown_json_fields: ${unknown.join(', ')}');
    }
    if (decoded['schema_version'] != 1 ||
        decoded['explanation'] is! String ||
        decoded['placement'] is! String ||
        decoded['operation'] is! String ||
        decoded['code'] is! String ||
        decoded['warnings'] is! List) {
      throw const LlmException('invalid_llm_schema');
    }

    final operation = switch (decoded['operation'] as String) {
      'insert_at_cursor' => CodeOperation.insertAtCursor,
      'replace_selection' => CodeOperation.replaceSelection,
      'replace_file' => CodeOperation.replaceFile,
      'none' => CodeOperation.none,
      _ => throw const LlmException('invalid_operation'),
    };
    final warningsRaw = decoded['warnings'] as List;
    if (warningsRaw.any((item) => item is! String)) {
      throw const LlmException('invalid_warnings');
    }
    final explanation = (decoded['explanation'] as String).trim();
    final placement = (decoded['placement'] as String).trim();
    final code = decoded['code'] as String;
    if (explanation.isEmpty || placement.isEmpty) {
      throw const LlmException('empty_explanation_or_placement');
    }
    if (code.length > 100000) throw const LlmException('code_too_large');

    return LlmCodingResponse(
      schemaVersion: 1,
      explanation: explanation,
      placement: placement,
      operation: operation,
      code: code,
      warnings: warningsRaw.cast<String>(),
    );
  }

  Uri _chatCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) return Uri.parse(trimmed);
    return Uri.parse('$trimmed/chat/completions');
  }

  Uri _anthropicMessagesUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/messages')) return Uri.parse(trimmed);
    return Uri.parse('$trimmed/messages');
  }

  Future<http.Response> testConnection(AppSettings settings) {
    _validateSettings(settings);
    return switch (settings.apiProvider) {
      ExternalApiProvider.openAiCompatible => _postOpenAi(
          _chatCompletionsUri(settings.apiBaseUrl),
          settings,
          {
            'model': settings.apiModel,
            'max_tokens': 1,
            'messages': const [
              {'role': 'user', 'content': 'Return OK.'},
            ],
          },
        ),
      ExternalApiProvider.anthropic => _postAnthropic(
          _anthropicMessagesUri(settings.apiBaseUrl),
          settings,
          {
            'model': settings.apiModel,
            'max_tokens': 1,
            'messages': const [
              {'role': 'user', 'content': 'Return OK.'},
            ],
          },
        ),
    };
  }

  String _contentToString(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((item) => item['text'])
          .whereType<String>()
          .join();
    }
    throw const LlmException('invalid_message_content');
  }

  String _safeBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 500 ? compact : '${compact.substring(0, 500)}…';
  }

  void dispose() => _client.close();
}

class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}
