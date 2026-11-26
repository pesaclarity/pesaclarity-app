// iPhone's Paste messages and the About you questions, for the
// accessibility check (tool/accessibility.sh): each at every text size, in
// light and dark. Not marketing screenshots, so tool/screenshots.sh skips
// them.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/about_you/about_you.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/onboarding/application/about_you_providers.dart';
import 'package:pesaclarity/src/features/onboarding/presentation/about_you_cards.dart';
import 'package:pesaclarity/src/features/onboarding/presentation/about_you_screen.dart';
import 'package:pesaclarity/src/features/sms/application/paste_messages.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/presentation/paste_messages_screen.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 11, 22, 6, 41);

void main() {
  if (!checkAccessibility) return;

  final mpesa = institutionCatalogue.singleWhere((i) => i.id == 'mpesa');
  final pasted =
      '${mpesaSent().body}\n${mpesaTill().body}\n\n${mpesaNotice().body}';

  Future<void> pump(WidgetTester tester, Widget screen) async {
    final AppDatabase db = openTestDatabase();
    final ingestor = SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db),
      reviewInbox: DriftReviewInboxRepository(db, clock: () => _now),
      reads: MessageReadsRepository(db),
      parse: (packs, messages) async => parseAll(packs, messages),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => _now),
          deviceRegionProvider.overrideWithValue('KE'),
          selectedInstitutionsProvider.overrideWithValue([mpesa]),
          clipboardTextProvider.overrideWithValue(() async => pasted),
          pasteReaderProvider.overrideWithValue(
            PasteReader(
              parse: (packs, messages) async => parseAll(packs, messages),
              ingestor: ingestor,
              now: () => _now,
              reads: MessageReadsRepository(db),
              storedKeys: (keys) => storedDedupeKeys(db, keys),
            ),
          ),
          aboutYouGoalProvider.overrideWith(
            (ref) async => const GoalSuggestion(
              name: 'Emergency fund',
              reason: 'You said saving steadily matters.',
              halfMonth: false,
              targetMinor: 5700000,
              monthlyMinor: 475000,
            ),
          ),
          ...appLockOverrides(),
        ],
        child: shotApp(screen),
      ),
    );
    await settleFrames(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settleFrames(tester);
    await tester.pumpAndSettle();
  }

  screenshot('paste-messages', (tester) async {
    await pump(tester, const PasteMessagesScreen());
    await snap(tester);
  });

  screenshot('paste-messages-pasted', (tester) async {
    await pump(tester, const PasteMessagesScreen());
    await tapKey(tester, 'paste-button');
    await snap(tester);
  });

  screenshot('paste-messages-found', (tester) async {
    await pump(tester, const PasteMessagesScreen());
    await tapKey(tester, 'paste-button');
    await tapKey(tester, 'paste-read');
    await snap(tester);
  });

  screenshot('paste-messages-added', (tester) async {
    await pump(tester, const PasteMessagesScreen());
    await tapKey(tester, 'paste-button');
    await tapKey(tester, 'paste-read');
    await tapKey(tester, 'paste-add');
    await snap(tester);
  });

  screenshot('about-you-who', (tester) async {
    await pump(tester, const AboutYouScreen());
    await tapKey(tester, 'about-why');
    await tapKey(tester, 'who-working');
    await snap(tester);
  });

  screenshot('about-you-matters', (tester) async {
    await pump(tester, const AboutYouScreen());
    await tapKey(tester, 'about-continue');
    await tapKey(tester, 'matters-saveSteadily');
    await snap(tester);
  });

  screenshot('about-you-pays', (tester) async {
    await pump(tester, const AboutYouScreen());
    await tapKey(tester, 'about-continue');
    await tapKey(tester, 'about-continue');
    await tapKey(tester, 'about-why');
    await tapKey(tester, 'pays-groceries');
    await tapKey(tester, 'pays-dataAirtime');
    // Back to the top, so no row is half under the bar.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('about-you-offers', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            MakeItYoursCard(onAnswer: () {}),
            const SizedBox(height: 16),
            MakeItYoursCard(onAnswer: () {}, onClose: () {}),
            const SizedBox(height: 16),
            const AboutYouGoalOffer(),
          ],
        ),
      ),
    );
    await snap(tester);
  });
}
