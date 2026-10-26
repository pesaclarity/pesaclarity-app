import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/accounts/application/my_accounts_providers.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';

void main() {
  test('catalogue ids match the ujumbe pack ids', () {
    expect(institutionCatalogue.map((i) => i.id), ['mpesa', 'im_bank', 'kcb']);
    for (final institution in institutionCatalogue) {
      expect(institution.senderIds, isNotEmpty, reason: institution.id);
    }
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
