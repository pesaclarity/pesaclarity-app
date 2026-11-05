import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/semantic_ids.dart';

import '../helpers/test_app.dart';

// The Maestro flows in .maestro/ select widgets by these identifiers. This
// test fails first if a refactor drops one.
void main() {
  Future<void> tapId(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await tester.pumpAndSettle();
  }

  void expectId(String id) {
    expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
  }

  void expectChecked(WidgetTester tester, String id, {required bool checked}) {
    expect(
      tester.getSemantics(find.bySemanticsIdentifier(id)),
      isSemantics(
        identifier: id,
        hasCheckedState: true,
        isChecked: checked,
        hasToggledState: false,
      ),
      reason: id,
    );
  }

  test('institution ids use hyphens', () {
    expect(SemanticIds.institution('mpesa'), 'institution-mpesa');
    expect(SemanticIds.institution('im_bank'), 'institution-im-bank');
    expect(SemanticIds.currency('KES'), 'currency-KES');
    expect(SemanticIds.incomeSource('salary'), 'income-salary');
  });

  testAppWidgets('every screen the UI flows visit exposes its identifiers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, db: openTestDatabase());

    expectId(SemanticIds.titleWelcome);
    await tapId(tester, SemanticIds.onboardingGetStarted);
    expectId(SemanticIds.titleCurrency);
    // As the flows do: search for KES, then tap its row by id.
    await tester.enterText(find.byKey(const Key('currency-search')), 'KES');
    await tester.pumpAndSettle();
    expectChecked(tester, SemanticIds.currency('KES'), checked: true);
    await tapId(tester, SemanticIds.currency('KES'));
    await tapId(tester, SemanticIds.onboardingCurrencyContinue);
    expectId(SemanticIds.titleIncomeSources);
    expectChecked(tester, SemanticIds.incomeSource('salary'), checked: false);
    await tapId(tester, SemanticIds.incomeSource('salary'));
    expectChecked(tester, SemanticIds.incomeSource('salary'), checked: true);
    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.onboardingIncomeContinue),
    );
    await tapId(tester, SemanticIds.onboardingIncomeContinue);
    expectId(SemanticIds.titleMyAccounts);
    expectId(SemanticIds.institution('im_bank'));
    expectId(SemanticIds.institution('kcb'));
    expectChecked(tester, SemanticIds.institution('mpesa'), checked: false);
    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.onboardingScanMessages),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier(SemanticIds.onboardingScanMessages),
      ),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticIds.institution('mpesa')),
      -300,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await tester.pumpAndSettle();
    await tapId(tester, SemanticIds.institution('mpesa'));
    expectChecked(tester, SemanticIds.institution('mpesa'), checked: true);
    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.onboardingScanMessages),
    );
    await tapId(tester, SemanticIds.onboardingScanMessages);
    expectId(SemanticIds.titleSmsScan);
    await tapId(tester, SemanticIds.smsScanNotNow);
    expectId(SemanticIds.titleHome);

    const tabs = {
      SemanticIds.navActivity: SemanticIds.titleActivity,
      SemanticIds.navPlan: SemanticIds.titlePlan,
      SemanticIds.navGoals: SemanticIds.titleGoals,
      SemanticIds.navInsights: SemanticIds.titleInsights,
      SemanticIds.navHome: SemanticIds.titleHome,
    };
    for (final MapEntry(key: tab, value: title) in tabs.entries) {
      await tapId(tester, tab);
      expectId(title);
    }

    await tapId(tester, SemanticIds.homeProfile);
    expectId(SemanticIds.titleProfile);

    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.profileMyAccounts),
    );
    await tapId(tester, SemanticIds.profileMyAccounts);
    expectId(SemanticIds.titleProfileMyAccounts);
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier(SemanticIds.institution('mpesa')),
      ),
      isSemantics(hasToggledState: true, isToggled: true),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.profileBackup),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticIds.profileBackup));
    // The backup screen shows a spinner until settings load; don't settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expectId(SemanticIds.titleBackup);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.profilePrivacy),
    );
    await tapId(tester, SemanticIds.profilePrivacy);
    expectId(SemanticIds.titlePrivacy);

    await tapId(tester, SemanticIds.navGoals);
    await scrollTo(
      tester,
      find.bySemanticsIdentifier(SemanticIds.goalsSeeDebts),
    );
    await tapId(tester, SemanticIds.goalsSeeDebts);
    expectId(SemanticIds.titleDebts);

    semantics.dispose();
  });
}
