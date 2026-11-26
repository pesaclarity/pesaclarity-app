// The first scan on a realistic inbox: 2,000 made-up M-Pesa and KCB
// messages over six months, read during setup on the real router and
// providers, timed from Allow access until Home shows its figures.
//
// HOST numbers, as in hot_paths_benchmark_test.dart: an in-memory database
// on the test's own isolate, and the readers on it too (the app reads in a
// background isolate). They catch a scan that turns slow; they do not say
// how long a phone takes.
//
// Print the times:
//   flutter test test/perf/first_scan_benchmark_test.dart --dart-define=PERF_REPORT=true
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:ujumbe/ujumbe.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/test_app.dart';

const _report = bool.fromEnvironment('PERF_REPORT');

/// How many messages the inbox holds; 2,000 unless set.
const _messages = int.fromEnvironment(
  'FIRST_SCAN_MESSAGES',
  defaultValue: 2000,
);

/// Generous, in host seconds of wall time: five to ten times what the
/// whole run took on the machine that set it (5 to 12 s on a shared,
/// busy one), so load does not fail it; a scan or Home that turns
/// quadratic would.
const _ceilingSeconds = 60;

/// Saturday 21 November 2026, 12:00 EAT.
final _now = DateTime.utc(2026, 11, 21, 9);

/// `26/10/26 at 9:15 AM` for an East Africa time.
String _when(DateTime eat) {
  final h = eat.hour % 12 == 0 ? 12 : eat.hour % 12;
  final m = eat.minute.toString().padLeft(2, '0');
  final d = eat.day.toString().padLeft(2, '0');
  final mo = eat.month.toString().padLeft(2, '0');
  final y = (eat.year % 100).toString().padLeft(2, '0');
  return '$d/$mo/$y at $h:$m ${eat.hour < 12 ? 'AM' : 'PM'}';
}

String _ksh(int shillings) {
  final text = shillings.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$text.00';
}

/// [count] made-up messages, ten a day back from [_now]: money in, people
/// paid, tills, bills, cash out, airtime and bank debits, with fake names
/// and masked fake numbers.
List<SmsMessage> syntheticInbox(int count) {
  final messages = <SmsMessage>[];
  // High enough that no balance printed goes below zero.
  var balance = 500000;
  for (var i = 0; i < count; i++) {
    final day = i ~/ 10;
    final slot = i % 10;
    // East Africa time, and the UTC the phone stamps it with.
    final eat = DateTime.utc(
      _now.year,
      _now.month,
      _now.day,
      7 + slot,
      (i * 7) % 60,
    ).subtract(Duration(days: day + 1));
    final at = eat.subtract(const Duration(hours: 3));
    final receipt = 'TK${(i + 1).toString().padLeft(8, '0')}';
    final amount = 50 + (i * 37) % 2400;
    final who = 'PERSON ${String.fromCharCode(65 + i % 26)} DOE';
    final String body;
    final String sender;
    switch (slot) {
      case 0:
        balance += amount * 6;
        sender = 'MPESA';
        body =
            '$receipt Confirmed.You have received Ksh${_ksh(amount * 6)} '
            'from $who 0700***${i % 900 + 100} on ${_when(eat)}  New '
            'M-PESA balance is Ksh${_ksh(balance)}.';
      case 1 || 4 || 7:
        balance -= amount;
        sender = 'MPESA';
        body =
            '$receipt Confirmed. Ksh${_ksh(amount)} sent to $who '
            '0700***${i % 900 + 100} on ${_when(eat)}. New M-PESA balance '
            'is Ksh${_ksh(balance)}. Transaction cost, Ksh15.00. Amount you '
            'can transact within the day is 498,500.00.';
      case 2 || 5:
        balance -= amount;
        sender = 'MPESA';
        body =
            '$receipt Confirmed. Ksh${_ksh(amount)} paid to EXAMPLE SHOP '
            '${i % 40}. on ${_when(eat)}.New M-PESA balance is '
            'Ksh${_ksh(balance)}. Transaction cost, Ksh0.00. Amount you can '
            'transact within the day is 496,950.00.';
      case 3:
        balance -= amount;
        sender = 'MPESA';
        body =
            '$receipt Confirmed. Ksh${_ksh(amount)} sent to EXAMPLE POWER '
            'LTD for account 1234567890 on ${_when(eat)} New M-PESA balance '
            'is Ksh${_ksh(balance)}. Transaction cost, Ksh15.00.Amount you '
            'can transact within the day is 497,300.00.';
      case 6:
        balance -= 100;
        sender = 'MPESA';
        body =
            '$receipt confirmed.You bought Ksh100.00 of airtime on '
            '${_when(eat)}.New M-PESA balance is Ksh${_ksh(balance)}. '
            'Transaction cost, Ksh0.00.';
      case 8:
        balance -= amount;
        sender = 'MPESA';
        body =
            '$receipt Confirmed.on ${_when(eat)}Withdraw Ksh${_ksh(amount)} '
            'from 123456 - EXAMPLE AGENT SHOP NAIROBI New M-PESA balance is '
            'Ksh${_ksh(balance)}. Transaction cost, Ksh29.00.';
      default:
        sender = 'KCB';
        final d = eat.day.toString().padLeft(2, '0');
        final mo = eat.month.toString().padLeft(2, '0');
        body =
            'Dear Customer, KES ${_ksh(amount)} has been debited from your '
            'account ****0001 on $d/$mo/${eat.year} at '
            '${eat.hour.toString().padLeft(2, '0')}:'
            '${eat.minute.toString().padLeft(2, '0')}. Transaction Ref: '
            'KCB${(i + 1).toString().padLeft(10, '0')}. Your available '
            'balance is KES 70,000.00.';
    }
    messages.add(
      SmsMessage(
        sender: sender,
        body: body,
        receivedAt: at.add(const Duration(seconds: 5)),
      ),
    );
  }
  return messages;
}

void main() {
  setUp(() {
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  testAppWidgets('the first scan of 2,000 messages reaches Home', (
    tester,
  ) async {
    final sms = FakeSmsSource(inbox: syntheticInbox(_messages));
    addTearDown(sms.close);
    final db = openTestDatabase();
    await pumpApp(
      tester,
      db: db,
      sms: sms,
      overrides: [clockProvider.overrideWithValue(() => _now)],
    );
    await getStarted(tester);
    await tapText(tester, 'M-Pesa');
    await tapText(tester, 'KCB');
    await tapText(tester, 'Scan my messages');

    final watch = Stopwatch()..start();
    await tapText(tester, 'Allow access to messages');
    await settleFrames(tester);
    await tester.pumpAndSettle();
    final scanned = watch.elapsed;
    expect(find.text('Found $_messages transactions'), findsOneWidget);

    await tapText(tester, 'Continue');
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text('Everything so far'), findsOneWidget);
    final insight = watch.elapsed;

    await tapText(tester, 'Go to Home');
    // Home's lead card with its figure: work on the database between
    // frames until it shows.
    final figure = find.descendant(
      of: find.byKey(const Key('home-safe')),
      matching: find.textContaining('KES '),
    );
    for (var i = 0; i < 60 && figure.evaluate().isEmpty; i++) {
      await settleFrames(tester);
    }
    expect(figure, findsWidgets);
    final home = watch.elapsed;

    final stored = await tester.runAsync(
      () => db.select(db.transactions).get(),
    );
    if (_report) {
      // ignore: avoid_print
      print(
        'First scan of ${sms.inbox.length} messages '
        '(${stored!.length} transactions): read '
        '${scanned.inMilliseconds} ms, first insight '
        '${(insight - scanned).inMilliseconds} ms, Home '
        '${(home - insight).inMilliseconds} ms; Allow access to Home '
        '${home.inMilliseconds} ms',
      );
    }
    // Agent withdrawals and deposits also write their side in Cash in hand.
    expect(
      stored!.where((t) => t.source != TransactionSource.manual),
      hasLength(_messages),
    );
    expect(home.inSeconds, lessThan(_ceilingSeconds));
  });
}
