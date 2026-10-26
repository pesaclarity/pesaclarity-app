import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

const _markdown = '''
# Privacy policy

## The short version

Your money stays
on your phone.

## What our server holds

**Sign-in**

Your account id.

- One
- Two
''';

PrivacyPolicy _policy(String version, {List<Map<String, Object?>>? changes}) =>
    PrivacyPolicy.fromAssets(
      metadata: {
        'version': version,
        'updated': '2026-10-26',
        'changes':
            changes ??
            [
              {
                'version': '1.0',
                'date': '2026-10-26',
                'items': ['First version.'],
              },
            ],
      },
      markdown: _markdown,
    );

void main() {
  group('PolicyVersion', () {
    test('compares part by part', () {
      PolicyVersion v(String s) => PolicyVersion.parse(s);
      expect(v('1.10').isNewerThan(v('1.9')), isTrue);
      expect(v('2.0').isNewerThan(v('1.10')), isTrue);
      expect(v('1.0'), v('1'));
      expect(v('1.0').isNewerThan(v('1')), isFalse);
      expect(() => v('1.x'), throwsFormatException);
    });
  });

  group('PrivacyPolicy', () {
    test('reads the bundled format', () {
      final policy = _policy('1.0');
      expect(policy.title, 'Privacy policy');
      expect(policy.version, PolicyVersion.parse('1.0'));
      expect(policy.updated, CalendarDate(2026, 10, 26));
      expect(policy.versionLine, 'Version 1.0 · updated 26 Oct 2026');
      expect(policy.blocks.map((b) => (b.type, b.text)), [
        (PolicyBlockType.heading, 'The short version'),
        (PolicyBlockType.paragraph, 'Your money stays on your phone.'),
        (PolicyBlockType.heading, 'What our server holds'),
        (PolicyBlockType.term, 'Sign-in'),
        (PolicyBlockType.paragraph, 'Your account id.'),
        (PolicyBlockType.bullet, 'One'),
        (PolicyBlockType.bullet, 'Two'),
      ]);
    });

    test('lists changes since a version, newest first', () {
      final policy = _policy(
        '1.2',
        changes: [
          for (final v in ['1.0', '1.1', '1.2', '1.3'])
            {
              'version': v,
              'date': '2026-11-01',
              'items': ['Change $v'],
            },
        ],
      );
      expect(
        policy.changesSince(PolicyVersion.parse('1.0')).map((c) => c.items),
        [
          ['Change 1.2'],
          ['Change 1.1'],
        ],
      );
    });

    test('renders plain text for email', () {
      final text = _policy('1.0').toPlainText();
      expect(text, startsWith('Privacy policy\nVersion 1.0, updated 26 Oct'));
      expect(text, contains('THE SHORT VERSION\n\nYour money stays'));
      expect(text, contains('- One\n- Two'));
    });
  });

  group('ConsentRecord', () {
    final at = DateTime.utc(2026, 10, 26, 9);
    final v1 = PolicyVersion.parse('1.0');

    test('uses the defaults until set', () {
      const record = ConsentRecord();
      expect(record.valueOf(ConsentKind.improveApp), isTrue);
      expect(record.valueOf(ConsentKind.licensedModels), isFalse);
      expect(record.valueOf(ConsentKind.crashReports), isFalse);
      expect(record.needsReview(_policy('2.0')), isFalse);
    });

    test('keeps the version and time of each choice through JSON', () {
      final record = const ConsentRecord()
          .accept(v1, at: at, values: {ConsentKind.crashReports: true})
          .withChoice(
            ConsentKind.licensedModels,
            true,
            at: at.add(const Duration(days: 1)),
            policyVersion: v1,
          );
      final restored = ConsentRecord.fromJson(record.toJson());
      expect(restored.acceptedVersion, v1);
      expect(restored.acceptedAt, at);
      expect(restored.valueOf(ConsentKind.improveApp), isTrue);
      expect(restored.valueOf(ConsentKind.crashReports), isTrue);
      final licensed = restored.choices[ConsentKind.licensedModels]!;
      expect(licensed.value, isTrue);
      expect(licensed.changedAt, at.add(const Duration(days: 1)));
      expect(licensed.policyVersion, v1);
    });

    test('asks again for a newer policy and pauses optional uses', () {
      final record = const ConsentRecord().accept(v1, at: at, values: {});
      final newer = _policy('1.1');
      expect(record.needsReview(_policy('1.0')), isFalse);
      expect(record.needsReview(newer), isTrue);
      expect(record.allows(ConsentKind.improveApp, _policy('1.0')), isTrue);
      expect(record.allows(ConsentKind.improveApp, newer), isFalse);
    });
  });
}
