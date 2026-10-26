import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/features/accounts/application/my_accounts_providers.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:ujumbe/ujumbe.dart';

void main() {
  test('the catalogue is the bundled parser packs, mobile money first', () {
    expect(institutionCatalogue.map((i) => i.id), ['mpesa', 'im_bank', 'kcb']);
    expect(
      institutionCatalogue.map((i) => i.id).toSet(),
      bundledPackIds.toSet(),
    );
    for (final institution in institutionCatalogue) {
      expect(institution.senderIds, isNotEmpty, reason: institution.id);
      expect(institution.senderIds, institution.pack.senders);
    }
    expect(institutionCatalogue.first.name, 'M-Pesa');
    expect(institutionCatalogue.first.type, AccountType.mpesa);
    expect(institutionCatalogue.last.type, AccountType.bank);
  });

  test('the watch list holds only the selected senders', () {
    expect(senderWatchList(institutionCatalogue, {}), isEmpty);
    expect(senderWatchList(institutionCatalogue, {'mpesa', 'kcb'}), {
      'MPESA',
      'KCB',
    });
    expect(senderWatchList(institutionCatalogue, {'unknown'}), isEmpty);
  });
}
