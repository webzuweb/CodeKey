import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'models.dart';

class LlmService {
  LlmService({http.Client? client, AppLogger? logger})
      : _client = client ?? http.Client(),
        _logger = logger ?? AppLogger.instance;

  final http.Client _client;
  final AppLogger _logger;

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
    final stopwatch = Stopwatch()..start();
    try {
      final result = switch (settings.apiProvider) {
        ExternalApiProvider.openAiCompatible => _completeOpenAiCompatible(
            settings: settings,
            request: request,
            code: code,
          ),
        ExternalApiProvider.deepSeek => _completeDeepSeek(
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
      final response = await result;
      _logger.info('llm.http_completed', {
        'provider': settings.apiProvider.name,
        'host': _safeHost(settings.apiBaseUrl),
        'model': settings.apiModel,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      return response;
    } on Object catch (error, stackTrace) {
      _logger.error(
        'llm.http_failed',
        error,
        stackTrace: stackTrace,
        data: {
          'provider': settings.apiProvider.name,
          'host': _safeHost(settings.apiBaseUrl),
          'model': settings.apiModel,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      rethrow;
    }
  }

  Future<LlmCodingResponse> _completeOpenAiCompatible({
    required AppSettings settings,
    required String request,
    required String code,
  }) => _completeOpenAiStyle(
    settings: settings,
    request: request,
    code: code,
    deepSeek: false,
  );

  Future<LlmCodingResponse> _completeDeepSeek({
    required AppSettings settings,
    required String request,
    required String code,
  }) => _completeOpenAiStyle(
    settings: settings,
    request: request,
    code: code,
    deepSeek: true,
  );

  Future<LlmCodingResponse> _completeOpenAiStyle({
    required AppSettings settings,
    required String request,
    required String code,
    required bool deepSeek,
  }) async {
    final endpoint = _chatCompletionsUri(settings.apiBaseUrl);
    final body = <String, Object?>{
      'model': settings.apiModel.trim(),
      'temperature': 0.1,
      'max_tokens': 8192,
      if (deepSeek) 'thinking': {'type': 'disabled'},
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
    if (response.statusCode == 400 && !deepSeek) {
      // Some OpenAI-compatible gateways do not implement response_format.
      final retryBody = Map<String, Object?>.from(body)..remove('response_format');
      _logger.warning('llm.response_format_retry', {
        'provider': settings.apiProvider.name,
        'host': endpoint.host,
      });
      response = await _postOpenAi(endpoint, settings, retryBody);
    }
    _requireSuccess(response);

    final decoded = _decodeEnvelope(response.body);
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

    final decoded = _decodeEnvelope(response.body);
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
    final uri = Uri.tryParse(settings.apiBaseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const LlmException('invalid_api_url');
    }
  }

  void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final details = _safeApiError(response.body);
      throw LlmException(
        details.isEmpty
            ? 'api_http_${response.statusCode}'
            : 'api_http_${response.statusCode}: $details',
      );
    }
  }

  Map<String, dynamic> _decodeEnvelope(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmException('invalid_api_envelope');
    }
    return decoded;
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
      ExternalApiProvider.deepSeek => _postOpenAi(
          _chatCompletionsUri(settings.apiBaseUrl),
          settings,
          {
            'model': settings.apiModel,
            'max_tokens': 1,
            'thinking': const {'type': 'disabled'},
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

  String _safeApiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final type = error['type']?.toString().trim() ?? '';
          final code = error['code']?.toString().trim() ?? '';
          final message = error['message']?.toString().trim() ?? '';
          final fields = [type, code, message]
              .where((item) => item.isNotEmpty)
              .join(' — ');
          return _truncate(fields, 300);
        }
      }
    } on Object {
      // Deliberately do not include a raw body: a gateway may echo source code.
    }
    return '';
  }

  String _safeHost(String value) => Uri.tryParse(value)?.host ?? '<invalid-url>';

  String _truncate(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';

  void dispose() => _client.close();
}

class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}
