import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/shared/semantic_ids.dart';

// The Maestro flows in .maestro/ select widgets by these identifiers. This
// test fails first if a refactor drops one.
void main() {
  Future<void> tapId(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
  }

  void expectId(String id) {
    expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
  }

  testWidgets('every screen the UI flows visit exposes its identifiers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appFlavorProvider.overrideWithValue(AppFlavor.foss)],
        child: const PesaClarityApp(),
      ),
    );
    await tester.pumpAndSettle();

    expectId(SemanticIds.titleWelcome);
    await tapId(tester, SemanticIds.onboardingGetStarted);
    expectId(SemanticIds.titleMyAccounts);
    await tapId(tester, SemanticIds.onboardingStartScan);
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

    await tester.tap(find.text('Backup and restore'));
    await tester.pumpAndSettle();
    expectId(SemanticIds.titleBackup);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expectId(SemanticIds.titlePrivacy);

    await tapId(tester, SemanticIds.navGoals);
    await tester.tap(find.text('See debts'));
    await tester.pumpAndSettle();
    expectId(SemanticIds.titleDebts);

    semantics.dispose();
  });
}
