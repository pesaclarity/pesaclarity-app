// Each account is read in one space, or shared through Business or
// personal: a second space never switches it on, and an account two spaces
// read already is left to Personal. Made-up data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/presentation/institution_list.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

const _shop = Space(
  id: 'shop1',
  name: 'Mama Njeri Shop',
  kind: SpaceKind.business,
);

SmsMessage _paid(String receipt, int shillings, int day) => mpesaSms(
  '$receipt Confirmed. Ksh$shillings.00 paid to EXAMPLE GROCERS. on '
  '$day/11/26 at 1:45 PM.New M-PESA balance is Ksh29,650.00. Transaction '
  'cost, Ksh0.00.',
  DateTime.utc(2026, 11, day, 10, 45, 5),
);

SmsMessage _received(String receipt, DateTime at) => mpesaSms(
  '$receipt Confirmed.You have received Ksh650.00 from TEST CUSTOMER '
  '0700***002 on 20/11/26 at 11:30 AM  New M-PESA balance is '
  'Ksh30,300.00.',
  at,
);

void main() {
  late AppDatabase personal;
  late AppDatabase other;
  late PhoneInbox phone;

  Future<Set<String?>> receipts(AppDatabase db) async => {
    for (final t in await db.select(db.transactions).get()) t.receiptNo,
  };

  Future<Set<String>> lines(AppDatabase db) =>
      DriftInstitutionsRepository(db).selectedIds();

  Future<ProviderContainer> app({
    Space space = _shop,
    String open = personalSpaceId,
  }) async {
    if (space.kind != SpaceKind.personal) await other.becomeSpace(space.kind);
    await DriftAppSettingsRepository(personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson([Space.personal, space]),
    );
    return twoSpaces(
      personal: personal,
      other: other,
      sms: phone,
      clock: () => DateTime.utc(2026, 11, 20, 9),
      active: open,
    );
  }

  setUp(() async {
    personal = openTestDatabase();
    other = openTestDatabase();
    phone = PhoneInbox();
    addTearDown(phone.close);
    await DriftInstitutionsRepository(personal)
        .setSelected('mpesa', selected: true);
  });

  test('a shop switching on M-Pesa, which Personal reads: it stays off, '
      'and each payment is in one space', () async {
    final c = await app();
    final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    addTearDown(shell.close);
    phone
      ..receive(_paid('TJA0000401', 12000, 1))
      ..receive(_paid('TJA0000402', 350, 10));
    await until(() async => (await receipts(personal)).length == 2);
    await captureIsSteady(phone);

    await c.read(activeSpaceIdProvider.notifier).switchTo(_shop.id);
    await c
        .read(institutionsRepositoryProvider)
        .setSelected('mpesa', selected: true);
    await captureIsSteady(phone);
    phone.receive(_received('TJA0000403', DateTime.now().toUtc()));
    await settle();
    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
    await until(() async => (await receipts(personal)).length == 3);
    await settle();

    expect(await lines(other), isEmpty);
    expect(await receipts(other), isEmpty);
    expect(await receipts(personal), {
      'TJA0000401',
      'TJA0000402',
      'TJA0000403',
    });
    expect(
      lineChoiceOf(
        inBusiness: (await lines(other)).contains('mpesa'),
        inPersonal: (await lines(personal)).contains('mpesa'),
        shared: (await c.read(routingRulesProvider.future))
            .sharedWith(_shop.id)
            .contains('mpesa'),
      ),
      LineChoice.personal,
    );
  });

  test('an account no other space reads switches on', () async {
    final c = await app(open: _shop.id);
    await c
        .read(institutionsRepositoryProvider)
        .setSelected('kcb', selected: true);
    expect(await lines(other), {'kcb'});
  });

  test('Personal switching on an account a shop reads: it stays off', () async {
    final (c, _) = await spacesOnFiles(clock: () => DateTime.utc(2026, 11, 20));
    await c.read(spacesProvider.notifier).add('First shop', SpaceKind.business);
    await c
        .read(institutionsRepositoryProvider)
        .setSelected('kcb', selected: true);
    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);

    await c
        .read(institutionsRepositoryProvider)
        .setSelected('kcb', selected: true);
    expect(await c.read(institutionsRepositoryProvider).selectedIds(), isEmpty);
    // One no space reads does.
    await c
        .read(institutionsRepositoryProvider)
        .setSelected('mpesa', selected: true);
    expect(await c.read(institutionsRepositoryProvider).selectedIds(), {
      'mpesa',
    });
  });

  test('two businesses: the second does not switch on what the first '
      'reads', () async {
    final (c, _) = await spacesOnFiles(clock: () => DateTime.utc(2026, 11, 20));
    final first = await c
        .read(spacesProvider.notifier)
        .add('First shop', SpaceKind.business);
    await c
        .read(institutionsRepositoryProvider)
        .setSelected('kcb', selected: true);
    final second = await c
        .read(spacesProvider.notifier)
        .add('Second shop', SpaceKind.business);
    expect(c.read(activeSpaceIdProvider), second);

    final reader = await c
        .read(institutionsRepositoryProvider)
        .setSelected('kcb', selected: true)
        .then((_) => c.read(institutionsRepositoryProvider).selectedIds());
    expect(reader, isEmpty);
    await c.read(activeSpaceIdProvider.notifier).switchTo(first);
    expect(await c.read(institutionsRepositoryProvider).selectedIds(), {'kcb'});
  });

  group('Business or personal still moves an account', () {
    Future<void> choose(ProviderContainer c, LineChoice choice) => c
        .read(routingRulesProvider.notifier)
        .setLine(
          'mpesa',
          choice,
          businessId: _shop.id,
          business: c.read(institutionsRepositoryProvider),
          personal: DriftInstitutionsRepository(personal),
        );

    test('to the shop only, and back to both', () async {
      final c = await app(open: _shop.id);

      await choose(c, LineChoice.thisBusiness);
      expect(await lines(other), {'mpesa'});
      expect(await lines(personal), isEmpty);

      await choose(c, LineChoice.both);
      expect(await lines(other), isEmpty);
      expect(await lines(personal), {'mpesa'});
      expect((await c.read(routingRulesProvider.future)).sharedLines, {
        'mpesa': _shop.id,
      });
    });
  });

  group('an account two spaces read already', () {
    Future<void> openWithCapture(ProviderContainer c) async {
      final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
      addTearDown(shell.close);
      await captureIsSteady(phone);
      await settle();
    }

    test('is shared with Personal when the business opens, so each '
        'payment is read once and the business asks about it', () async {
      await DriftInstitutionsRepository(other)
          .setSelected('mpesa', selected: true);
      final c = await app(open: _shop.id);
      await openWithCapture(c);

      expect(await lines(other), isEmpty);
      expect((await c.read(routingRulesProvider.future)).sharedLines, {
        'mpesa': _shop.id,
      });

      await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
      await captureIsSteady(phone);
      phone.receive(_received('TJA0000404', DateTime.now().toUtc()));
      await until(() async => (await receipts(personal)).isNotEmpty);
      await c.read(activeSpaceIdProvider.notifier).switchTo(_shop.id);
      await settle();
      expect(await receipts(other), isEmpty);
      expect(
        [
          for (final q
              in await c.read(sharedLineRouterProvider).pending(_shop.id))
            q.name,
        ],
        ['TEST CUSTOMER'],
      );
    });

    test('is left to Personal by a household, with no rule', () async {
      await DriftInstitutionsRepository(other)
          .setSelected('mpesa', selected: true);
      final c = await app(
        space: const Space(
          id: 'home1',
          name: 'Our home',
          kind: SpaceKind.household,
        ),
        open: 'home1',
      );
      await openWithCapture(c);

      expect(await lines(other), isEmpty);
      expect(await lines(personal), {'mpesa'});
      expect((await c.read(routingRulesProvider.future)).isEmpty, isTrue);
    });

    test('stays shared with the business it was shared with', () async {
      await DriftInstitutionsRepository(other)
          .setSelected('mpesa', selected: true);
      await DriftAppSettingsRepository(personal).writeJson(
        RoutingRulesController.settingsKey,
        const RoutingRules(sharedLines: {'mpesa': 'shop2'}).toJson(),
      );
      await DriftAppSettingsRepository(personal).writeJson(
        SpacesController.settingsKey,
        spacesToJson([
          Space.personal,
          _shop,
          const Space(id: 'shop2', name: 'Shop two', kind: SpaceKind.business),
        ]),
      );
      await other.becomeSpace(SpaceKind.business);
      final c = twoSpaces(
        personal: personal,
        other: other,
        sms: phone,
        clock: () => DateTime.utc(2026, 11, 20, 9),
        active: _shop.id,
      );
      await openWithCapture(c);

      expect(await lines(other), isEmpty);
      expect((await c.read(routingRulesProvider.future)).sharedLines, {
        'mpesa': 'shop2',
      });
    });
  });

  test('read once: only a business shares, and never a line shared '
      'with another', () {
    const rules = RoutingRules(sharedLines: {'kcb': 'shop2'});
    expect(
      rules
          .readOnce({'mpesa', 'kcb'}, spaceId: 'shop1', business: true)
          .sharedLines,
      {'kcb': 'shop2', 'mpesa': 'shop1'},
    );
    expect(
      rules.readOnce({'mpesa'}, spaceId: 'home1', business: false).sharedLines,
      {'kcb': 'shop2'},
    );
  });

  testAppWidgets('switching it on in the shop leads to Business or '
      'personal', (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async => c = await app(open: _shop.id));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: InstitutionList(control: InstitutionControl.toggle),
          ),
        ),
        GoRoute(
          path: AppRoutes.businessOrPersonal,
          builder: (_, _) => const Scaffold(body: Text('Where it goes')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.runAsync(() => c.read(spacesProvider.future));
    await tester.pumpAndSettle();

    await tester.tap(find.text('M-Pesa'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal reads M-Pesa'), findsOneWidget);
    expect(
      find.text(
        'Each account is read in one space. Choose in Business or personal '
        'whether its money is for Mama Njeri Shop, Personal or both.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Where it goes'), findsOneWidget);
    expect(await tester.runAsync(() => lines(other)), isEmpty);
  });
}
