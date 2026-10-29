import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled policy loads, mirroring the website page', () async {
    final policy = await loadBundledPolicy(rootBundle);
    expect(policy.title, 'Privacy policy');
    expect(policy.version, PolicyVersion.parse('1.3'));
    expect(policy.changes.first.version, policy.version);
    expect(
      policy.blocks
          .where((b) => b.type == PolicyBlockType.heading)
          .map((b) => b.text),
      [
        'The short version',
        'What stays on your phone',
        'What our server holds',
        'Exchange rates',
        'Your choices',
        'Your rights',
        'This website',
        'Questions',
      ],
    );
  });
}
