import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled policy loads, mirroring the website page', () async {
    final policy = await loadBundledPolicy(rootBundle);
    expect(policy.title, 'Privacy policy');
    expect(policy.version, PolicyVersion.parse('1.4'));
    expect(policy.changes.first.version, policy.version);
    expect(
      policy.blocks
          .where((b) => b.type == PolicyBlockType.heading)
          .map((b) => b.text),
      [
        'The short version',
        'What stays on your phone',
        'What our server holds',
        'Who runs our server',
        'Exchange rates',
        'Your choices',
        'Keeping it safe',
        'Your rights',
        'This website',
        'Changes',
        'Questions',
      ],
    );
  });

  test('the bundled terms load', () async {
    final terms = await loadBundledDocument(rootBundle, 'terms');
    expect(terms.title, 'Terms');
    expect(terms.version, PolicyVersion.parse('1.0'));
    expect(terms.changes.first.version, terms.version);
    expect(
      terms.blocks
          .where((b) => b.type == PolicyBlockType.heading)
          .map((b) => b.text),
      contains('Kenyan law'),
    );
  });
}
