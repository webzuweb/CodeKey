import 'package:codekey_app/dlp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret and internal host are detected and redacted', () {
    final service = DlpService();
    final report = service.scan(
      request: 'Fix connection',
      code: 'const password = "VerySecret123";\nfinal host = "api.bank.local";',
      corporateTerms: 'PaymentCore',
    );
    expect(report.findings, isNotEmpty);
    final redacted = service.redact(
      request: 'Fix connection',
      code: 'const password = "VerySecret123";\nfinal host = "api.bank.local";',
      report: report,
    );
    expect(redacted.code, isNot(contains('VerySecret123')));
    expect(redacted.code, contains('__SECRET_1__'));
  });

  test('the same sensitive value gets one stable placeholder', () {
    final service = DlpService();
    final report = service.scan(
      request: 'Check api.bank.local',
      code: 'const host = "api.bank.local";',
      corporateTerms: '',
    );
    final hostFindings = report.findings
        .where((finding) => finding.type == 'INTERNAL_HOST')
        .toList();
    expect(hostFindings, hasLength(2));
    expect(hostFindings.first.placeholder, hostFindings.last.placeholder);
  });
}
