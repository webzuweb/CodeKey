import 'dart:math';

import 'models.dart';

class RedactedContent {
  const RedactedContent({required this.request, required this.code});
  final String request;
  final String code;
}

class DlpService {
  DlpReport scan({
    required String request,
    required String code,
    required String corporateTerms,
  }) {
    final findings = <DlpFinding>[
      ..._scanText('request', request, corporateTerms),
      ..._scanText('code', code, corporateTerms),
    ];
    return DlpReport(findings: _assignGlobalPlaceholders(findings));
  }

  List<DlpFinding> _assignGlobalPlaceholders(List<DlpFinding> findings) {
    final ordered = [...findings]..sort((a, b) {
      final sourceA = a.source == 'request' ? 0 : 1;
      final sourceB = b.source == 'request' ? 0 : 1;
      final source = sourceA.compareTo(sourceB);
      if (source != 0) return source;
      return a.start.compareTo(b.start);
    });
    final counters = <String, int>{};
    final byIdentity = <String, String>{};
    return ordered.map((finding) {
      final identity = '${finding.type}:${finding.value}';
      final placeholder = byIdentity.putIfAbsent(identity, () {
        final index = (counters[finding.type] ?? 0) + 1;
        counters[finding.type] = index;
        return '__${finding.type}_${index}__';
      });
      return DlpFinding(
        source: finding.source,
        type: finding.type,
        severity: finding.severity,
        start: finding.start,
        end: finding.end,
        value: finding.value,
        maskedPreview: finding.maskedPreview,
        placeholder: placeholder,
      );
    }).toList(growable: false);
  }

  RedactedContent redact({
    required String request,
    required String code,
    required DlpReport report,
  }) {
    return RedactedContent(
      request: _apply(request, report.findings.where((item) => item.source == 'request')),
      code: _apply(code, report.findings.where((item) => item.source == 'code')),
    );
  }

  List<DlpFinding> _scanText(String source, String text, String corporateTerms) {
    if (text.isEmpty) return const [];
    final candidates = <_Candidate>[];

    void addRegex(
      RegExp pattern,
      String type,
      DlpSeverity severity, {
      int group = 0,
      bool Function(String value)? predicate,
    }) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(group);
        if (value == null || value.isEmpty || !(predicate?.call(value) ?? true)) continue;
        final whole = match.group(0) ?? value;
        final localOffset = group == 0 ? 0 : whole.lastIndexOf(value);
        if (localOffset < 0) continue;
        candidates.add(_Candidate(
          type: type,
          severity: severity,
          start: match.start + localOffset,
          end: match.start + localOffset + value.length,
          value: value,
        ));
      }
    }

    addRegex(
      RegExp(r'''-----BEGIN[ A-Z0-9_-]*PRIVATE KEY-----[\s\S]*?-----END[ A-Z0-9_-]*PRIVATE KEY-----''', caseSensitive: false),
      'PRIVATE_KEY',
      DlpSeverity.critical,
    );
    addRegex(
      RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'),
      'JWT',
      DlpSeverity.critical,
    );
    addRegex(
      RegExp(
        r'''(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|passwd|pwd|client[_-]?secret|private[_-]?key)\s*[:=]\s*["']?([A-Za-z0-9_./+\-=]{8,})''',
        caseSensitive: false,
      ),
      'SECRET',
      DlpSeverity.critical,
      group: 1,
    );
    addRegex(
      RegExp(r'''\b(?:AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})\b'''),
      'KNOWN_API_TOKEN',
      DlpSeverity.critical,
    );
    addRegex(
      RegExp(
        r'''\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp|mssql):\/\/[^\s"']+''',
        caseSensitive: false,
      ),
      'CONNECTION_STRING',
      DlpSeverity.critical,
    );
    addRegex(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
      'EMAIL',
      DlpSeverity.medium,
    );
    addRegex(
      RegExp(r'\b(?:[A-Za-z0-9-]+\.)+(?:local|internal|corp|lan)\b', caseSensitive: false),
      'INTERNAL_HOST',
      DlpSeverity.high,
    );
    addRegex(
      RegExp(r'''(?:[A-Za-z]:\\(?:[^\r\n<>:"|?*]+\\)+[^\r\n<>:"|?*]*)|(?:\/(?:home|Users|opt|srv|var)\/[^\s"']+)''', caseSensitive: false),
      'FILE_PATH',
      DlpSeverity.medium,
    );

    for (final match in RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(text)) {
      final value = match.group(0)!;
      if (_isPrivateIpv4(value)) {
        candidates.add(_Candidate(
          type: 'INTERNAL_IP',
          severity: DlpSeverity.high,
          start: match.start,
          end: match.end,
          value: value,
        ));
      }
    }

    addRegex(
      RegExp(r'\+?[1-9](?:[ ()-]*\d){9,14}'),
      'PHONE',
      DlpSeverity.medium,
      predicate: (value) => value.replaceAll(RegExp(r'\D'), '').length >= 10,
    );

    for (final match in RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b', caseSensitive: false).allMatches(text)) {
      final value = match.group(0)!;
      if (_passesIban(value)) {
        candidates.add(_Candidate(
          type: 'IBAN',
          severity: DlpSeverity.high,
          start: match.start,
          end: match.end,
          value: value,
        ));
      }
    }

    for (final match in RegExp(r'\b(?:\d[ -]?){13,19}\b').allMatches(text)) {
      final value = match.group(0)!;
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 13 && digits.length <= 19 && _passesLuhn(digits)) {
        candidates.add(_Candidate(
          type: 'PAYMENT_CARD',
          severity: DlpSeverity.critical,
          start: match.start,
          end: match.end,
          value: value,
        ));
      }
    }

    final secretContext = RegExp(
      r'key|token|secret|password|credential|authorization|bearer|signature',
      caseSensitive: false,
    );
    for (final match in RegExp(r'\b[A-Za-z0-9_+/=-]{20,}\b').allMatches(text)) {
      final value = match.group(0)!;
      if (_entropy(value) < 4.0) continue;
      final from = max(0, match.start - 45);
      final to = min(text.length, match.end + 45);
      if (!secretContext.hasMatch(text.substring(from, to))) continue;
      candidates.add(_Candidate(
        type: 'HIGH_ENTROPY_SECRET',
        severity: DlpSeverity.high,
        start: match.start,
        end: match.end,
        value: value,
      ));
    }

    final terms = corporateTerms
        .split(RegExp(r'[,;\n]'))
        .map((term) => term.trim())
        .where((term) => term.length >= 3)
        .toSet();
    for (final term in terms) {
      final pattern = RegExp(RegExp.escape(term), caseSensitive: false);
      for (final match in pattern.allMatches(text)) {
        candidates.add(_Candidate(
          type: 'CORPORATE_TERM',
          severity: DlpSeverity.high,
          start: match.start,
          end: match.end,
          value: match.group(0)!,
        ));
      }
    }

    return _deduplicate(source, candidates);
  }

  List<DlpFinding> _deduplicate(String source, List<_Candidate> candidates) {
    candidates.sort((a, b) {
      final severity = b.severity.index.compareTo(a.severity.index);
      if (severity != 0) return severity;
      final length = (b.end - b.start).compareTo(a.end - a.start);
      if (length != 0) return length;
      return a.start.compareTo(b.start);
    });

    final accepted = <_Candidate>[];
    for (final candidate in candidates) {
      final overlaps = accepted.any(
        (item) => candidate.start < item.end && candidate.end > item.start,
      );
      if (!overlaps) accepted.add(candidate);
    }
    accepted.sort((a, b) => a.start.compareTo(b.start));

    final counters = <String, int>{};
    final placeholdersByValue = <String, String>{};
    return accepted.map((candidate) {
      final identity = '${candidate.type}:${candidate.value}';
      final placeholder = placeholdersByValue.putIfAbsent(identity, () {
        final next = (counters[candidate.type] ?? 0) + 1;
        counters[candidate.type] = next;
        return '__${candidate.type}_${next}__';
      });
      return DlpFinding(
        source: source,
        type: candidate.type,
        severity: candidate.severity,
        start: candidate.start,
        end: candidate.end,
        value: candidate.value,
        maskedPreview: _maskedPreview(candidate.value),
        placeholder: placeholder,
      );
    }).toList(growable: false);
  }

  String _apply(String original, Iterable<DlpFinding> findings) {
    var result = original;
    final sorted = findings.toList()..sort((a, b) => b.start.compareTo(a.start));
    for (final finding in sorted) {
      if (finding.start >= 0 && finding.end <= result.length && finding.start < finding.end) {
        result = result.replaceRange(finding.start, finding.end, finding.placeholder);
      }
    }
    return result;
  }

  bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null || part! > 255)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 || a == 127 || (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254);
  }

  bool _passesIban(String input) {
    final compact = input.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (compact.length < 15 || compact.length > 34) return false;
    final rearranged = compact.substring(4) + compact.substring(0, 4);
    var remainder = 0;
    for (final code in rearranged.codeUnits) {
      final fragment = code >= 0x41 && code <= 0x5A
          ? '${code - 0x41 + 10}'
          : String.fromCharCode(code);
      for (final digit in fragment.codeUnits) {
        if (digit < 0x30 || digit > 0x39) return false;
        remainder = (remainder * 10 + digit - 0x30) % 97;
      }
    }
    return remainder == 1;
  }

  bool _passesLuhn(String digits) {
    var sum = 0;
    var alternate = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var value = int.parse(digits[i]);
      if (alternate) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  double _entropy(String value) {
    final counts = <int, int>{};
    for (final unit in value.codeUnits) {
      counts[unit] = (counts[unit] ?? 0) + 1;
    }
    var entropy = 0.0;
    for (final count in counts.values) {
      final probability = count / value.length;
      entropy -= probability * (log(probability) / log(2));
    }
    return entropy;
  }

  String _maskedPreview(String value) {
    if (value.length <= 4) return '••••';
    final bullets = List<String>.filled(min(12, value.length - 4), '•').join();
    return '${value.substring(0, 2)}$bullets${value.substring(value.length - 2)}';
  }
}

class _Candidate {
  const _Candidate({
    required this.type,
    required this.severity,
    required this.start,
    required this.end,
    required this.value,
  });

  final String type;
  final DlpSeverity severity;
  final int start;
  final int end;
  final String value;
}
