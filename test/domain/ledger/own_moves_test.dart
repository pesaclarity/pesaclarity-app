import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/own_accounts.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';

// Decision 0030: one rule that stops double entries for every account.
// Each side as the readers leave it. Made-up names, numbers and codes.

const mpesa = 1; // M-Pesa line 0700000001
const airtel = 2; // Airtel Money 0730000000
const kcb = 3; // KCB 1234****456
const loop = 4; // Loop 0099****0001
const im = 5; // I&M 0020****0002
const equity = 6; // Equity 0170****0003
const etica = 7; // Etica fund 000000M
const coop = 8; // Co-op 0112****0004

final own = OwnAccounts(const [
  OwnAccount(id: mpesa, reference: '0700000001', institutionId: 'mpesa'),
  OwnAccount(id: airtel, reference: '0730000000', institutionId: 'airtel'),
  OwnAccount(id: kcb, reference: '1234****456', institutionId: 'kcb'),
  OwnAccount(id: loop, reference: '0099****0001', institutionId: 'loop'),
  OwnAccount(id: im, reference: '0020****0002', institutionId: 'im_bank'),
  OwnAccount(id: equity, reference: '0170****0003', institutionId: 'equity'),
  OwnAccount(id: etica, reference: '000000M', institutionId: 'etica'),
  OwnAccount(id: coop, reference: '0112****0004', institutionId: 'co_op_bank'),
]);

final references = {
  mpesa: '0700000001',
  airtel: '0730000000',
  kcb: '1234****456',
  loop: '0099****0001',
  im: '0020****0002',
  equity: '0170****0003',
  etica: '000000M',
  coop: '0112****0004',
};

final noon = DateTime.utc(2026, 11, 14, 9);

LedgerEntry side(
  int id,
  int accountId,
  TransactionDirection direction,
  int amountKes, {
  TransactionKind kind = TransactionKind.bank,
  int minutes = 0,
  int feeKes = 0,
  PayeeIdentifierKind? cpKind,
  String? cpValue,
  String? cpName,
}) => LedgerEntry(
  id: id,
  accountId: accountId,
  occurredAt: noon.add(Duration(minutes: minutes)),
  amountMinor: amountKes * 100,
  feeMinor: feeKes * 100,
  direction: direction,
  kind: kind,
  counterpartyKind: cpKind,
  counterpartyValue: cpValue,
  counterpartyName: cpName,
);

LedgerEntry out(
  int id,
  int accountId,
  int amountKes, {
  TransactionKind kind = TransactionKind.bank,
  int minutes = 0,
  int feeKes = 0,
  PayeeIdentifierKind? cpKind,
  String? cpValue,
  String? cpName,
}) => side(
  id,
  accountId,
  TransactionDirection.outflow,
  amountKes,
  kind: kind,
  minutes: minutes,
  feeKes: feeKes,
  cpKind: cpKind,
  cpValue: cpValue,
  cpName: cpName,
);

LedgerEntry into(
  int id,
  int accountId,
  int amountKes, {
  TransactionKind kind = TransactionKind.received,
  int minutes = 0,
  PayeeIdentifierKind? cpKind,
  String? cpValue,
  String? cpName,
}) => side(
  id,
  accountId,
  TransactionDirection.inflow,
  amountKes,
  kind: kind,
  minutes: minutes,
  cpKind: cpKind,
  cpValue: cpValue,
  cpName: cpName,
);

List<TransferPair> find(
  List<LedgerEntry> entries, {
  Map<int, String?> receipts = const {},
  Map<int, String?> linked = const {},
  Map<String, bool> answers = const {},
}) => findOwnTransfers(
  entries,
  references: references,
  receipts: receipts,
  linked: linked,
  own: own,
  answers: answers,
);

MoveCertainty certainty(
  LedgerEntry o,
  LedgerEntry i, {
  Map<int, String?> receipts = const {},
  Map<int, String?> linked = const {},
  Map<String, bool> answers = const {},
}) => moveCertainty(
  o,
  i,
  references: references,
  receipts: receipts,
  linked: linked,
  own: own,
  answers: answers,
);

void main() {
  group('one code on two accounts is one move (rule 2)', () {
    test('Loop to M-Pesa: the code both print, hours apart', () {
      final o = out(1, loop, 5000);
      final i = into(2, mpesa, 5000, minutes: 180, cpName: 'LOOP B2C');
      const receipts = {1: 'TJA0000101', 2: 'TJA0000101'};
      expect(find([o, i], receipts: receipts), [const TransferPair(1, 2)]);
      expect(certainty(o, i, receipts: receipts), MoveCertainty.code);
    });

    test('Loop to M-Pesa with no code: a guess, asked about', () {
      final o = out(1, loop, 5000);
      final i = into(2, mpesa, 5000, minutes: 5, cpName: 'LOOP B2C');
      expect(find([o, i]), [const TransferPair(1, 2)]);
      expect(certainty(o, i), MoveCertainty.guess);
    });

    test("I&M to M-Pesa: I&M's Ref is M-Pesa's receipt", () {
      final o = out(3, im, 2500);
      final i = into(4, mpesa, 2500, minutes: 90, cpName: 'I&M BANK');
      const receipts = {3: 'TJA0000102', 4: 'TJA0000102'};
      expect(find([o, i], receipts: receipts), [const TransferPair(3, 4)]);
      expect(certainty(o, i, receipts: receipts), MoveCertainty.code);
    });

    test('Equity to M-Pesa: the M-Pesa ref Equity prints', () {
      final o = out(5, equity, 200, cpName: 'JANE DOE');
      final i = into(6, mpesa, 200, minutes: 60, cpName: 'EQUITY BULK 1');
      const receipts = {5: 'EQA0000000000001', 6: 'TJA0000002'};
      const linked = {5: 'TJA0000002'};
      expect(find([o, i], receipts: receipts, linked: linked), [
        const TransferPair(5, 6),
      ]);
      expect(
        certainty(o, i, receipts: receipts, linked: linked),
        MoveCertainty.code,
      );
    });

    test("KCB to M-Pesa: the M-PESA REF KCB's send to a wallet prints", () {
      final o = out(7, kcb, 1000, cpName: 'JANE DOE');
      final i = into(8, mpesa, 1000, minutes: 120, cpName: 'KCB 1');
      const receipts = {7: 'KCB0000000000003', 8: 'TJA0000001'};
      const linked = {7: 'TJA0000001'};
      expect(find([o, i], receipts: receipts, linked: linked), [
        const TransferPair(7, 8),
      ]);
    });

    test("M-Pesa to Airtel Money: Airtel's Sender TID", () {
      final o = out(
        9,
        mpesa,
        100,
        kind: TransactionKind.sent,
        feeKes: 15,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0730000000',
        cpName: 'AIRTEL MONEY',
      );
      final i = into(10, airtel, 100, minutes: 1, cpName: 'JANE DOE');
      const receipts = {9: 'TJA0000037', 10: 'TJA0000040'};
      const linked = {10: 'TJA0000037'};
      expect(find([o, i], receipts: receipts, linked: linked), [
        const TransferPair(9, 10),
      ]);
      expect(
        certainty(o, i, receipts: receipts, linked: linked),
        MoveCertainty.code,
      );
    });

    test("Etica to M-Pesa: Etica's Transaction ref", () {
      final o = out(11, etica, 400, kind: TransactionKind.withdrawal);
      final i = into(12, mpesa, 400, minutes: 240, cpName: 'ETICA CAPITAL');
      const receipts = {11: 'TJA0000035', 12: 'TJA0000035'};
      expect(find([o, i], receipts: receipts), [const TransferPair(11, 12)]);
    });
  });

  group('no shared code: one side names an own account (rule 3)', () {
    test('M-Pesa to a bank: a paybill payment for the own account', () {
      final o = out(
        13,
        mpesa,
        12000,
        kind: TransactionKind.paybill,
        cpKind: PayeeIdentifierKind.paybill,
        cpValue: 'kcb#1234***456',
        cpName: 'KCB',
      );
      final i = into(14, kcb, 12000, kind: TransactionKind.bank, minutes: 2);
      expect(find([o, i]), [const TransferPair(13, 14)]);
      expect(certainty(o, i), MoveCertainty.named);
    });

    test('M-Pesa to Co-op: the own account number at the paybill', () {
      final o = out(
        15,
        mpesa,
        3000,
        kind: TransactionKind.paybill,
        cpKind: PayeeIdentifierKind.paybill,
        cpValue: 'co op bank#01120000004',
      );
      final i = into(16, coop, 3000, kind: TransactionKind.bank, minutes: 4);
      expect(find([o, i]), [const TransferPair(15, 16)]);
      expect(certainty(o, i), MoveCertainty.named);
    });

    test('by own number: M-Pesa sent to the own Airtel number', () {
      final o = out(
        17,
        mpesa,
        500,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0730000000',
      );
      final i = into(18, airtel, 500, minutes: 3, cpName: 'JANE DOE');
      expect(find([o, i]), [const TransferPair(17, 18)]);
      expect(certainty(o, i), MoveCertainty.named);
    });

    test('by own number: money in that names the own KCB account', () {
      final o = out(19, kcb, 2500);
      final i = into(
        20,
        mpesa,
        2500,
        minutes: 10,
        cpKind: PayeeIdentifierKind.account,
        cpValue: '1234****456',
        cpName: 'JANE DOE',
      );
      expect(find([o, i]), [const TransferPair(19, 20)]);
      expect(certainty(o, i), MoveCertainty.named);
    });

    test('a fee difference is allowed, a larger gap is not', () {
      LedgerEntry sent(int id, int amount) => out(
        id,
        mpesa,
        amount,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0730000000',
      );
      // KES 1,030 left, KES 1,000 arrived: the KES 30 is a fee.
      expect(find([sent(21, 1030), into(22, airtel, 1000, minutes: 2)]), [
        const TransferPair(21, 22),
      ]);
      // KES 1,300 left: far more than a fee, two different payments.
      expect(
        find([sent(23, 1300), into(24, airtel, 1000, minutes: 2)]),
        isEmpty,
      );
    });

    test('within about 30 minutes', () {
      LedgerEntry sent(int id) => out(
        id,
        mpesa,
        800,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0730000000',
      );
      expect(find([sent(25), into(26, airtel, 800, minutes: 25)]), [
        const TransferPair(25, 26),
      ]);
      expect(find([sent(27), into(28, airtel, 800, minutes: 45)]), isEmpty);
    });

    test('a stranger with the same amount stays separate', () {
      // M-Pesa sent KES 1,000 to someone else's number; Airtel got KES
      // 1,000 two minutes later from another sender.
      final paid = out(
        29,
        mpesa,
        1000,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0711000002',
        cpName: 'JOHN DOE',
      );
      final got = into(30, airtel, 1000, minutes: 2, cpName: 'MARY DOE');
      expect(find([paid, got]), isEmpty);
      expect(movesApart(paid, got, references: references, own: own), isTrue);
    });

    test('a Sender TID that is not the send stays separate', () {
      final o = out(31, mpesa, 1000, kind: TransactionKind.sent);
      final i = into(32, airtel, 1000, minutes: 2, cpName: 'MARY DOE');
      expect(
        find(
          [o, i],
          receipts: const {31: 'TJA0000050', 32: 'TJA0000051'},
          linked: const {32: 'TJA9999999'},
        ),
        isEmpty,
      );
    });

    test('money that names another own account is not this move', () {
      // Paid to the own Co-op account, not to KCB.
      final o = out(
        33,
        mpesa,
        700,
        kind: TransactionKind.paybill,
        cpKind: PayeeIdentifierKind.paybill,
        cpValue: 'co op bank#01120000004',
      );
      final i = into(34, kcb, 700, kind: TransactionKind.bank, minutes: 1);
      expect(find([o, i]), isEmpty);
    });
  });

  group('when unsure, ask once, remembered per sender (rule 5)', () {
    final o = out(35, kcb, 4000);
    final i = into(36, mpesa, 4000, minutes: 3, cpName: 'KCB 1');

    test('a guess pairs, held as a move, and is asked about', () {
      expect(find([o, i]), [const TransferPair(35, 36)]);
      expect(certainty(o, i), MoveCertainty.guess);
      expect(moveSenderKey(o, i), 'name:KCB 1');
      expect(moveSenderName(o, i), 'KCB 1');
    });

    test('Yes for the sender pairs it without asking', () {
      final answers = {moveSenderKey(o, i): true};
      expect(find([o, i], answers: answers), [const TransferPair(35, 36)]);
      expect(certainty(o, i, answers: answers), MoveCertainty.person);
    });

    test('No for the sender leaves it apart', () {
      final answers = {moveSenderKey(o, i): false};
      expect(find([o, i], answers: answers), isEmpty);
    });

    test('an answer for another sender changes nothing', () {
      final answers = {'name:SOMEONE ELSE': false};
      expect(find([o, i], answers: answers), [const TransferPair(35, 36)]);
      expect(certainty(o, i, answers: answers), MoveCertainty.guess);
    });
  });

  group('OwnAccounts', () {
    test('reads own numbers however they are printed', () {
      LedgerEntry to(String phone) => out(
        1,
        mpesa,
        100,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: phone,
      );
      expect(own.namedBy(to('0730000000')), airtel);
      expect(own.namedBy(to('0730***000')), airtel);
      expect(own.namedBy(to('0711000002')), isNull);
      expect(own.phoneOf(airtel), '0730000000');
      expect(own.phoneOf(kcb), isNull);
    });

    test('never names the account the entry is on', () {
      final self = out(
        1,
        airtel,
        100,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0730000000',
      );
      expect(own.namedBy(self), isNull);
    });

    test('an M-Pesa line\'s key is never an own number (rule 3)', () {
      // A line's account is keyed `line:<id>` (decision 0026), whatever
      // its id reads like; only a number kept on an account is the
      // person's.
      const line = 9;
      final lines = OwnAccounts([
        const OwnAccount(id: mpesa, institutionId: 'mpesa'),
        OwnAccount(
          id: line,
          reference: lineReference('0722000009'),
          institutionId: 'mpesa',
        ),
        OwnAccount(
          id: kcb,
          reference: lineReference('1234567890'),
          institutionId: 'kcb',
        ),
      ]);
      final toPhone = out(
        1,
        mpesa,
        100,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0722000009',
      );
      final toAccount = out(
        2,
        mpesa,
        100,
        kind: TransactionKind.paybill,
        cpKind: PayeeIdentifierKind.account,
        cpValue: '1234567890',
      );
      expect(lines.namedBy(toPhone), isNull);
      expect(lines.namedBy(toAccount), isNull);
      expect(lines.phoneOf(line), isNull);
    });

    test('a number the person typed for a line is an own number', () {
      const line = 9;
      final lines = OwnAccounts([
        const OwnAccount(id: mpesa, institutionId: 'mpesa'),
        OwnAccount(
          id: line,
          reference: lineReference('2'),
          institutionId: 'mpesa',
          phone: '0712345678',
        ),
      ]);
      final toLine = out(
        1,
        mpesa,
        100,
        kind: TransactionKind.sent,
        cpKind: PayeeIdentifierKind.phone,
        cpValue: '0712***678',
      );
      expect(lines.namedBy(toLine), line);
      expect(lines.phoneOf(line), '0712345678');
    });
  });
}
