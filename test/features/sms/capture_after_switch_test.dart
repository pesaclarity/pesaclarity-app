// Right after a switch, the capture reads only the accounts the space just
// opened has switched on, never those of the space it left. Made-up data
// only.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/sms_samples.dart';
import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase personal;
  late AppDatabase shop;
  late PhoneInbox phone;

  Future<List<String?>> receipts(AppDatabase db) async => [
    for (final t in await db.select(db.transactions).get()) t.receiptNo,
  ];

  setUp(() async {
    personal = openTestDatabase();
    shop = openTestDatabase();
    await shop.becomeSpace(SpaceKind.business);
    phone = PhoneInbox();
    addTearDown(phone.close);
    phone
      ..receive(
        mpesaSms(
          'TJA0000601 Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on '
          '10/11/26 at 1:45 PM.New M-PESA balance is Ksh29,650.00. '
          'Transaction cost, Ksh0.00.',
          DateTime.utc(2026, 11, 10, 10, 45, 5),
        ),
      )
      ..receive(
        kcbSms(
          'Dear Customer, KES 3,000.00 has been debited from your account '
          '****0001 on 11/11/2026 at 10:20. Transaction Ref: KCB0000000601. '
          'Your available balance is KES 7,000.00.',
          DateTime.utc(2026, 11, 11, 7, 20, 5),
        ),
      );
    await DriftInstitutionsRepository(personal)
        .setSelected('mpesa', selected: true);
  });

  test(
    'a shop opened from Personal reads none of Personal\'s accounts',
    () async {
      final c = twoSpaces(
        personal: personal,
        other: shop,
        sms: phone,
        clock: () => DateTime.utc(2026, 11, 20),
      );
      final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
      addTearDown(shell.close);
      await until(() async => (await receipts(personal)).isNotEmpty);
      await captureIsSteady(phone);

      await c.read(activeSpaceIdProvider.notifier).switchTo('shop1');
      await captureIsSteady(phone);
      await settle();

      expect(await receipts(shop), isEmpty);
      expect(await receipts(personal), ['TJA0000601']);
    },
  );

  test('Personal opened from the shop reads only its own accounts', () async {
    await DriftInstitutionsRepository(shop).setSelected('kcb', selected: true);
    final c = twoSpaces(
      personal: personal,
      other: shop,
      sms: phone,
      clock: () => DateTime.utc(2026, 11, 20),
      active: 'shop1',
    );
    final shell = c.listen(liveSmsCaptureProvider, (_, _) {});
    addTearDown(shell.close);
    await until(() async => (await receipts(shop)).isNotEmpty);
    await captureIsSteady(phone);

    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
    await until(() async => (await receipts(personal)).isNotEmpty);
    await captureIsSteady(phone);
    await settle();

    expect(await receipts(personal), ['TJA0000601']);
    expect(await receipts(shop), ['KCB0000000601']);
  });
}
