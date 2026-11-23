// Many M-Pesa lines on one phone: old lines, the quick setup, roles, not
// tracking a line, merging a replaced SIM into its line and the quiet note
// on the first skipped message. Made-up names and amounts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';

final _now = DateTime.utc(2026, 11, 22, 12);

MpesaLine _line(
  String id,
  DateTime last, {
  int messages = 10,
  int balance = 100,
  String? sim,
  DateTime? first,
}) => MpesaLine(
  id: id,
  sims: sim == null ? const {} : {sim},
  lastAt: last,
  firstAt: first ?? last.subtract(const Duration(days: 30)),
  messages: messages,
  balanceMinor: balance * 100,
  balanceAt: last,
);

/// Six lines, as on a phone that has held six SIMs: 1 today, 5 three days
/// ago, then four old ones.
MpesaLines _six() => MpesaLines(
  split: true,
  lines: [
    _line('1', _now, messages: 412, balance: 12500, sim: 's1'),
    _line('2', DateTime.utc(2024, 9, 9), messages: 132, balance: 0, sim: 's2'),
    _line(
      '3',
      DateTime.utc(2025, 3, 14),
      messages: 116,
      balance: 860,
      sim: 's3',
    ),
    _line(
      '4',
      DateTime.utc(2026, 6, 2),
      messages: 38,
      balance: 1020,
      sim: 's4',
    ),
    _line(
      '5',
      DateTime.utc(2026, 11, 19),
      messages: 96,
      balance: 4210,
      sim: 's5',
    ),
    _line('6', DateTime.utc(2026, 7, 30), messages: 3, balance: 150, sim: 's6'),
  ],
);

LineFacts _paid(String sim, int balance, {String hash = 'x', int minute = 0}) =>
    LineFacts(
      hash: hash,
      at: _now.add(Duration(minutes: minute + 1)),
      sim: sim,
      amountMinor: 1000,
      inflow: false,
      balanceMinor: balance * 100,
    );

void main() {
  test('a line is old after 90 days with no message', () {
    expect(
      _line('a', _now.subtract(const Duration(days: 89))).isOld(_now),
      isFalse,
    );
    expect(
      _line('a', _now.subtract(const Duration(days: 91))).isOld(_now),
      isTrue,
    );
  });

  test('lines list newest first', () {
    expect(
      [for (final l in _six().newestFirst) l.id],
      ['1', '5', '6', '4', '3', '2'],
    );
  });

  group('quick setup', () {
    test('shows only with more than 2 lines, and hides once used', () {
      expect(_six().offersQuickSetup, isTrue);
      final two = MpesaLines(lines: _six().lines.take(2).toList());
      expect(two.offersQuickSetup, isFalse);
      final done = _six().keepTwoMostRecent();
      expect(done.offersQuickSetup, isFalse);
      // Kept across a save.
      expect(MpesaLines.fromJson(done.toJson()).offersQuickSetup, isFalse);
    });

    test('keeps the two newest as main and second, the rest not tracked', () {
      final done = _six().keepTwoMostRecent();
      expect(done.mainId, '1');
      expect(done.secondId, '5');
      expect([for (final l in done.tracked) l.id], ['1', '5']);
      expect(done.untrackedCount, 4);
      final again = MpesaLines.fromJson(done.toJson());
      expect(again.line('4')!.tracked, isFalse);
      expect(again.roleOf('1'), LineRole.main);
      expect(again.roleOf('5'), LineRole.second);
    });
  });

  test('a role tracks a line again and moves off the line that had it', () {
    var lines = _six().keepTwoMostRecent();
    lines = lines.withRole('4', LineRole.second);
    expect(lines.line('4')!.tracked, isTrue);
    expect(lines.secondId, '4');
    expect(lines.roleOf('5'), isNull);
    lines = lines.withRole('4', LineRole.main);
    expect(lines.mainId, '4');
    expect(lines.secondId, isNull);
  });

  group('not tracked', () {
    test('new messages from it are skipped; the first leaves a quiet note '
        'due, once', () {
      final lines = _six().untracked('4');
      final (next, place) = lines.place(_paid('s4', 1010, hash: 'a'));
      expect(place, const NotTracked('4'));
      expect(next.skipNote, SkipNote.due);
      expect(next.skippedLineId, '4');
      // Its balance chain carries on.
      expect(next.line('4')!.balanceMinor, 101000);
      final seen = next.skipNoteSeen();
      final (after, again) = seen.place(_paid('s4', 1000, hash: 'b'));
      expect(again, const NotTracked('4'));
      expect(after.skipNote, SkipNote.shown);
    });

    test('a message placed on it before is skipped when read again', () {
      var lines = _six();
      lines = lines.place(_paid('s4', 1010, hash: 'old')).$1.untracked('4');
      expect(
        lines.place(_paid('s4', 1010, hash: 'old')).$2,
        const NotTracked('4'),
      );
    });

    test('on iPhone, by balance alone, its messages are skipped too', () {
      final iphone = MpesaLines(
        split: true,
        lines: [
          _line('1', _now, balance: 5000),
          _line('2', _now.subtract(const Duration(days: 2)), balance: 700),
        ],
      ).untracked('2');
      final carried = LineFacts(
        hash: 'i1',
        at: _now.add(const Duration(minutes: 5)),
        amountMinor: 10000,
        inflow: false,
        balanceMinor: 60000,
      );
      expect(iphone.place(carried).$2, const NotTracked('2'));
      final mine = LineFacts(
        hash: 'i2',
        at: _now.add(const Duration(minutes: 6)),
        amountMinor: 10000,
        inflow: false,
        balanceMinor: 490000,
      );
      expect(iphone.place(mine).$2, const OnLine('1'));
    });
  });

  group('same line as', () {
    test('two lines become one; the balance continues from the newer', () {
      final lines = _six().copyWith(placed: {'p': '3'}).merged('3', '5');
      expect(lines.line('3'), isNull);
      final kept = lines.line('5')!;
      expect(kept.messages, 212);
      expect(kept.balanceMinor, 421000);
      expect(kept.sims, {'s3', 's5'});
      expect(kept.firstAt, DateTime.utc(2025, 2, 12));
      expect(lines.placed['p'], '5');
      // A message from the older SIM is now on the kept line.
      expect(lines.place(_paid('s3', 4200)).$2, const OnLine('5'));
    });

    test('merging into an older line still takes the newer balance', () {
      final lines = _six().merged('5', '3');
      expect(lines.line('3')!.balanceMinor, 421000);
    });

    test('a role follows the line it merged into', () {
      final lines = _six().withRole('3', LineRole.second).merged('3', '5');
      expect(lines.secondId, '5');
    });
  });

  test('the main line sorts first, then the second, then the rest', () {
    final lines = _six()
        .withRole('5', LineRole.main)
        .withRole('1', LineRole.second);
    expect(lines.rankOf('line:5'), 0);
    expect(lines.rankOf('line:1'), 1);
    expect(lines.rankOf('line:3'), 2);
    expect(lines.rankOf(null), 2);
  });

  test(
    'a typed number is kept plain, shown masked, and cleared when empty',
    () {
      var lines = _six().withNumber('5', '+254 712 345 678');
      expect(lines.line('5')!.number, '0712345678');
      expect(lines.line('5')!.maskedNumber, '0712 ••• 678');
      expect(lines.numbers, {'5': '0712345678'});
      expect(
        MpesaLines.fromJson(lines.toJson()).line('5')!.number,
        '0712345678',
      );
      lines = lines.withNumber('5', 'not a number');
      expect(lines.line('5')!.number, isNull);
      expect(lines.withNumber('5', '').numbers, isEmpty);
    },
  );

  test('an old save with no new fields reads as before', () {
    final lines = MpesaLines.fromJson({
      'lines': [
        {'id': '1', 'messages': 2},
      ],
    });
    expect(lines.line('1')!.tracked, isTrue);
    expect(lines.quickSetupDone, isFalse);
    expect(lines.skipNote, SkipNote.none);
    expect(lines.mainId, isNull);
  });
}
