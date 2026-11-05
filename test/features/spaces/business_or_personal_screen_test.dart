import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/business_or_personal_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

void main() {
  testAppWidgets('a line can be the business, personal or both', (
    tester,
  ) async {
    final personal = openTestDatabase();
    final business = openTestDatabase();
    await tester.runAsync(
      () =>
          DriftInstitutionsRepository(business)
              .setSelected('mpesa', selected: true),
    );
    final container = ProviderContainer(
      overrides: [
        personalDatabaseProvider.overrideWithValue(personal),
        appDatabaseProvider.overrideWithValue(business),
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId('shop1')),
        activeSpaceProvider.overrideWithValue(
          const Space(
            id: 'shop1',
            name: 'Vegetable stall',
            kind: SpaceKind.business,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BusinessOrPersonalScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Only Vegetable stall'), findsOneWidget);

    await tester.tap(find.byKey(const Key('line-choice-mpesa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask me').last);
    await tester.pumpAndSettle();

    expect(find.text('Used for both'), findsOneWidget);
    final lines = await tester.runAsync(
      () async => (
        await DriftInstitutionsRepository(business).selectedIds(),
        await DriftInstitutionsRepository(personal).selectedIds(),
      ),
    );
    expect(lines!.$1, isEmpty);
    expect(lines.$2, {'mpesa'});
    final rules = await tester.runAsync(
      () => container.read(routingRulesProvider.future),
    );
    expect(rules!.sharedWith('shop1'), {'mpesa'});
  });
}
