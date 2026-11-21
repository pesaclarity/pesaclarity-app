import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/message_twins.dart';

// Synthetic facts: invented references, names and amounts.

final _at = DateTime.utc(2026, 11, 7, 12, 15);

TwinFacts _wallet({
  String receipt = 'TJB0000031',
  String? name = 'KCB 1',
  String readBy = '0.3.0 mpesa@0.3.1',
  Duration after = Duration.zero,
  TransactionKind kind = TransactionKind.received,
  String hash = 'm1',
  String? twinHash,
}) => TwinFacts(
  at: _at.add(after),
  amountMinor: 250000,
  direction: TransactionDirection.inflow,
  currency: 'KES',
  kind: kind,
  receipt: receipt,
  messageHash: hash,
  twinHash: twinHash,
  counterpartyName: name,
  readBy: readBy,
);

TwinFacts _bank({
  String receipt = 'KCB0000000000031',
  String readBy = '0.3.0 kcb@0.2.0',
  Duration after = const Duration(seconds: 20),
  int amountMinor = 250000,
  String hash = 'k1',
  String? twinHash,
}) => TwinFacts(
  at: _at.add(after),
  amountMinor: amountMinor,
  direction: TransactionDirection.inflow,
  currency: 'KES',
  kind: TransactionKind.received,
  receipt: receipt,
  messageHash: hash,
  twinHash: twinHash,
  counterpartyName: 'MARY WAMBUI DOE',
  readBy: readBy,
);

void main() {
  test('packOf reads the pack from readBy', () {
    expect(packOf('0.3.0 kcb@0.2.0'), 'kcb');
    expect(packOf('0.3.0 mpesa@0.3.1'), 'mpesa');
    expect(packOf(null), isNull);
    expect(packOf('0.3.0'), isNull);
  });

  group('money into M-Pesa from KCB, told by both', () {
    test('is one, whichever was stored first', () {
      expect(twinMatch(_wallet(), _bank()), TwinMatch.walletCredit);
      expect(twinMatch(_bank(), _wallet()), TwinMatch.walletCredit);
      expect(walletCreditSide(_wallet(), _bank()), isTrue);
      expect(walletCreditSide(_bank(), _wallet()), isFalse);
    });

    test('M-Pesa may name KCB in more words', () {
      expect(
        twinMatch(_wallet(name: 'KCB BANK KENYA'), _bank()),
        TwinMatch.walletCredit,
      );
    });

    test('not when M-Pesa names someone else', () {
      expect(twinMatch(_wallet(name: 'JOHN KAMAU'), _bank()), isNull);
      expect(twinMatch(_wallet(name: 'KCBX TRADERS'), _bank()), isNull);
      expect(twinMatch(_wallet(name: null), _bank()), isNull);
    });

    test('not outside the twin window', () {
      expect(
        twinMatch(_wallet(after: const Duration(minutes: 16)), _bank()),
        isNull,
      );
    });

    test('not for different amounts', () {
      expect(twinMatch(_wallet(), _bank(amountMinor: 250100)), isNull);
    });

    test('not for two M-Pesa or two KCB messages', () {
      expect(
        twinMatch(_wallet(), _wallet(receipt: 'TJB0000032', hash: 'm2')),
        isNull,
      );
      expect(
        twinMatch(_bank(), _bank(receipt: 'KCB0000000000032', hash: 'k2')),
        isNull,
      );
    });

    test('not when either was not read by the packs', () {
      expect(twinMatch(_wallet(readBy: ''), _bank()), isNull);
      expect(twinMatch(_wallet(), _bank(readBy: '0.3.0 equity@0.1.0')), isNull);
    });

    test('not when M-Pesa\'s message is not money received', () {
      expect(twinMatch(_wallet(kind: TransactionKind.sent), _bank()), isNull);
    });

    test('a stored message already merged takes no second twin', () {
      expect(twinMatch(_wallet(twinHash: 'k0'), _bank()), isNull);
      // The same twin read again still finds it.
      expect(
        twinMatch(_wallet(twinHash: 'k1'), _bank()),
        TwinMatch.walletCredit,
      );
    });

    test('other different references stay two payments', () {
      expect(
        twinMatch(
          _wallet(name: 'JOHN KAMAU'),
          _wallet(receipt: 'TJB0000032', hash: 'm2', name: 'JOHN KAMAU'),
        ),
        isNull,
      );
    });
  });
}
