import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/features/security/application/device_integrity_providers.dart';
import 'package:pesaclarity/src/features/security/data/device_integrity_checker.dart';
import 'package:pesaclarity/src/features/security/data/device_warning_repository.dart';
import 'package:pesaclarity/src/features/security/domain/device_integrity.dart';
import 'package:pesaclarity/src/features/security/presentation/device_warning_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

class FakeChecker implements DeviceIntegrityChecker {
  const FakeChecker(this.report);

  final DeviceIntegrityReport report;

  @override
  Future<DeviceIntegrityReport> check() async => report;
}

const rooted = DeviceIntegrityReport(suBinary: true);

Future<void> pumpProfile(
  WidgetTester tester,
  AppDatabase db,
  DeviceIntegrityReport report,
) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceIntegrityCheckerProvider.overrideWithValue(FakeChecker(report)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('a clean phone shows no warning', (tester) async {
    final db = openTestDatabase();
    await pumpProfile(tester, db, DeviceIntegrityReport.clean);
    expect(find.text(DeviceWarningCard.title), findsNothing);
    expect(find.text('My accounts'), findsOneWidget);
  });

  testAppWidgets('a rooted phone shows the warning once', (tester) async {
    final db = openTestDatabase();
    await pumpProfile(tester, db, rooted);
    expect(find.text(DeviceWarningCard.title), findsOneWidget);
    // The rest of Profile stays usable.
    expect(find.text('My accounts'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text(DeviceWarningCard.title), findsNothing);
    expect(await DriftDeviceWarningRepository(db).isDismissed(), isTrue);

    await pumpProfile(tester, db, rooted);
    expect(find.text(DeviceWarningCard.title), findsNothing);
  });
}
