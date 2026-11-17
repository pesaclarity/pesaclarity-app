import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/presentation/choose_accounts_screen.dart';
import 'package:pesaclarity/src/features/sms/application/read_again.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/sms/presentation/read_again_card.dart';
import 'package:pesaclarity/src/features/sms/presentation/read_again_home_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

/// A read held at [fixed], to show each of the card's states.
class _Held extends ReadAgainController {
  _Held(this.fixed);

  final ReadAgainState fixed;

  @override
  ReadAgainState build() => fixed;
}

final _now = DateTime.utc(2026, 11, 17, 9);

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name theme', () {
      late AppDatabase db;

      setUp(() => db = openTestDatabase());

      Future<void> pump(
        WidgetTester tester,
        Widget home, {
        ReadAgainState? held,
        SmsSource? sms,
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              smsSourceProvider.overrideWithValue(
                sms ?? FakeSmsSource(inbox: [mpesaSent(), mpesaTill()]),
              ),
              clockProvider.overrideWithValue(() => _now),
              smsParseBatchProvider.overrideWithValue(
                (packs, messages) async => parseAll(packs, messages),
              ),
              if (held != null)
                readAgainControllerProvider.overrideWith(() => _Held(held)),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(body: home),
            ),
          ),
        );
        await settleFrames(tester);
      }

      Future<void> tickMpesa(WidgetTester tester) => tester.runAsync(
        () =>
            DriftInstitutionsRepository(db)
                .setSelected('mpesa', selected: true),
      );

      testAppWidgets('My accounts: says when messages were last read, and '
          'reads them again', (tester) async {
        await tickMpesa(tester);
        await tester.runAsync(
          () => DriftAppSettingsRepository(db).writeJson(
            ReadAgainController.settingsKey,
            LastRead(
              readers: const ReaderVersions('0.3.0', {'mpesa': '0.3.1'}),
              at: DateTime.utc(2026, 11, 14, 8),
            ).toJson(),
          ),
        );
        await pump(tester, const ChooseAccountsScreen());
        await scrollTo(tester, find.byKey(const Key('read-again-card')));

        expect(find.text('Read messages again'), findsOneWidget);
        expect(
          find.text(
            'Reads your messages again with the latest readers, to catch '
            'any that were missed. Your names and categories stay.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Last read 14 Nov, with readers 0.3.0'),
          findsOneWidget,
        );
        // Under "Read messages from".
        expect(
          tester.getTopLeft(find.byKey(const Key('read-again-card'))).dy,
          greaterThan(tester.getTopLeft(find.text('Read messages from')).dy),
        );

        await tester.tap(find.text('Read again'));
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (find
              .byKey(const Key('read-again-result'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        expect(find.text('2 new, 0 updated'), findsOneWidget);
        expect(find.text('Read again just now · 2 messages'), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        expect(find.text('Read again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testAppWidgets('My accounts: while reading, and when it is done', (
        tester,
      ) async {
        await tickMpesa(tester);
        await pump(
          tester,
          const ReadAgainCard(),
          held: const ReadAgainState(
            ReadAgainStage.reading,
            done: 1240,
            total: 2960,
          ),
        );
        expect(find.text('Reading your messages again'), findsOneWidget);
        expect(
          find.text('1,240 of 2,960 messages · You can leave this screen'),
          findsOneWidget,
        );
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, closeTo(1240 / 2960, 0.001));
        expect(find.text('Read again'), findsNothing);

        await pump(
          tester,
          const ReadAgainCard(),
          held: ReadAgainState(
            ReadAgainStage.finished,
            total: 2960,
            at: _now,
            summary: SmsIngestSummary(
              added: 12,
              updated: 3,
              changes: [ReadChange('kcb', 1, DateTime.utc(2026, 11, 3))],
            ),
          ),
        );
        expect(find.text('12 new, 3 updated'), findsOneWidget);
        expect(
          find.text('Read again just now · 2,960 messages'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        expect(find.text('Read again'), findsOneWidget);

        await pump(
          tester,
          const ReadAgainCard(),
          held: ReadAgainState(ReadAgainStage.finished, total: 2960, at: _now),
        );
        expect(find.text('Nothing new'), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });

      testAppWidgets('My accounts: hidden with no account ticked, or on '
          'iPhone', (tester) async {
        await pump(tester, const ReadAgainCard());
        expect(find.byKey(const Key('read-again-card')), findsNothing);

        await tickMpesa(tester);
        await tester.pumpWidget(const SizedBox());
        await pump(tester, const ReadAgainCard());
        expect(find.byKey(const Key('read-again-card')), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await pump(
          tester,
          const ReadAgainCard(),
          sms: const ShortcutSmsSource(),
        );
        expect(find.byKey(const Key('read-again-card')), findsNothing);
      });

      testAppWidgets('Home: shows what newer readers found until closed', (
        tester,
      ) async {
        await pump(tester, const ReadAgainHomeCard());
        expect(find.byKey(const Key('home-read-again')), findsNothing);

        await tester.runAsync(
          () => DriftAppSettingsRepository(db).writeJson(
            ReadAgainController.noticeKey,
            const ReadAgainNotice(
              added: 12,
              updated: 3,
              institutionIds: ['equity', 'kcb'],
            ).toJson(),
          ),
        );
        await tester.pumpWidget(const SizedBox());
        await pump(tester, const ReadAgainHomeCard());
        expect(find.text('Newer readers found 12 payments'), findsOneWidget);
        expect(
          find.textContaining(
            RegExp(r'^Messages from .+ and .+ were read again$'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('home-read-again-close')));
        await settleFrames(tester);
        expect(find.byKey(const Key('home-read-again')), findsNothing);
        final saved = await tester.runAsync(
          () =>
              DriftAppSettingsRepository(db)
                  .readJson(ReadAgainController.noticeKey),
        );
        expect(ReadAgainNotice.fromJson(saved), isNull);
      });
    });
  }

  test('names read as a list', () {
    expect(namesList(['Equity']), 'Equity');
    expect(namesList(['Equity', 'KCB']), 'Equity and KCB');
    expect(namesList(['Equity', 'KCB', 'M-Pesa']), 'Equity, KCB and M-Pesa');
  });

  test('counts are grouped, and Activity narrows to what changed', () {
    expect(countLabel(7), '7');
    expect(countLabel(2960), '2,960');
    expect(countLabel(1234567), '1,234,567');
    final filter = changedFilter([
      ReadChange('kcb', 4, DateTime.utc(2026, 11, 3, 6)),
      ReadChange('kcb', 4, DateTime.utc(2026, 10, 30, 6)),
    ]);
    expect(filter.accountId, 4);
    expect(filter.from, CalendarDate(2026, 10, 30));
    expect(filter.to, CalendarDate(2026, 11, 3));
    expect(
      changedFilter([
        ReadChange('kcb', 4, DateTime.utc(2026, 11, 3, 6)),
        ReadChange('equity', 5, DateTime.utc(2026, 11, 3, 6)),
      ]).accountId,
      isNull,
    );
  });
}
