import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_answer.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';

/// Made-up records, the fact sheets the app builds from them and the system
/// text. pesaclarity-ml's training data copies this file and checks its own
/// fact sheet writer gives the same text, word for word
/// (tests/test_slm_facts.py there). Run with UPDATE_SLM_PARITY=1 to write it
/// again after a change to SlmFacts, then copy it to pesaclarity-ml.
const _fixture = 'test/features/slm_experiment/fixtures/slm_facts_parity.json';

const _names = {
  1: 'Groceries and household', 2: 'Rent and housing', 3: 'Transport', //
  4: 'Eating out', 5: 'Airtime and data', 6: 'Betting and gaming',
  7: 'Shopping and clothing', 8: 'Salary',
};
const _payees = [
  'DEMO GROCERS', 'SAMPLE LANDLORD', 'TEST MATATU SACCO', 'FAKE CAFE', //
  'DEMO TELCO', 'SAMPLE BETS', 'TEST KALI MOTE', null,
];

Map<String, Object?> _case(int seed) {
  final r = Random(seed);
  final today = CalendarDate(2026, 1 + r.nextInt(12), 1 + r.nextInt(28));
  final from = today.yearMonth.addMonths(-3).firstDay;
  final span = from.daysUntil(today) + 1;
  var id = 0;
  final entries = <LedgerEntry>[];
  for (var i = 0, n = r.nextInt(90); i < n; i++) {
    final day = from.addDays(r.nextInt(span));
    final at = day.startInstant.add(Duration(hours: 6 + r.nextInt(14)));
    final roll = r.nextDouble();
    final cat = r.nextInt(10); // 0 and 9: not sorted and an unknown id
    entries.add(
      LedgerEntry(
        id: ++id,
        accountId: 1,
        occurredAt: at,
        amountMinor: (r.nextInt(200) + 1) * (r.nextBool() ? 5000 : 1750),
        direction: roll < 0.2
            ? TransactionDirection.inflow
            : TransactionDirection.outflow,
        kind: roll < 0.2 ? TransactionKind.received : TransactionKind.till,
        categoryId: roll < 0.2 ? 8 : (cat == 0 ? null : cat),
        categoryType: roll < 0.2
            ? (r.nextInt(8) == 0 ? CategoryType.expense : CategoryType.income)
            : (r.nextInt(12) == 0
                  ? CategoryType.savings
                  : CategoryType.expense),
        payeeId: 1,
        payeeName: _payees[r.nextInt(_payees.length)],
        feeMinor: r.nextBool() ? 0 : r.nextInt(30) * 100,
      ),
    );
  }
  final payday = r.nextInt(4) == 0
      ? null
      : today.addDays(-r.nextInt(40) + 3); // sometimes after today
  final input = SlmFactsInput(
    today: today,
    entries: entries,
    lastPayday: payday,
    categoryNames: _names,
    balances: [
      for (var i = 0, n = r.nextInt(4); i < n; i++)
        SlmLine(
          ['M-Pesa', 'KCB', 'M-Shwari', 'Cash'][i],
          r.nextInt(5000000) - 100000,
          savings: i == 2,
        ),
    ],
    bills: [
      for (var i = 0, n = r.nextInt(4); i < n; i++)
        SlmLine(
          ['Internet', 'Rent', 'School fees', 'Water'][i],
          r.nextInt(3000000),
          date: r.nextInt(5) == 0 ? null : today.addDays(r.nextInt(30) - 5),
        ),
    ],
    budgets: [
      for (var i = 0, n = r.nextInt(5); i < n; i++)
        SlmBudget(
          _names[i + 1]!,
          (r.nextInt(40) + 1) * 50000,
          r.nextInt(3000000),
        ),
    ],
    feesThisMonthMinor: r.nextInt(3) == 0 ? r.nextInt(90000) : null,
  );
  String date(CalendarDate d) => d.toString();
  return {
    'today': date(today),
    'last_payday': payday == null ? null : date(payday),
    'entries': [
      for (final e in entries)
        {
          'date': date(CalendarDate.local(e.occurredAt)),
          'income_minor': incomeOf(e),
          'spending_minor': spendingOf(e),
          'fee_minor': e.feeMinor,
          'category': e.categoryId == null
              ? null
              : _names[e.categoryId] ?? 'Other',
          'payee': (e.payeeName ?? e.counterpartyName)?.trim(),
        },
    ],
    'balances': [
      for (final b in input.balances)
        {'name': b.name, 'amount_minor': b.amountMinor, 'savings': b.savings},
    ],
    'bills': [
      for (final b in input.bills)
        {
          'name': b.name,
          'amount_minor': b.amountMinor,
          'date': b.date == null ? null : date(b.date!),
        },
    ],
    'budgets': [
      for (final b in input.budgets)
        {
          'name': b.name,
          'planned_minor': b.plannedMinor,
          'used_minor': b.usedMinor,
        },
    ],
    'fees_this_month_minor': input.feesThisMonthMinor,
    'text': SlmFacts.of(input).text,
  };
}

void main() {
  test('the fact sheets match the ones pesaclarity-ml trains on', () {
    final now = {
      'system_prompt': slmSystemPrompt,
      'cases': [for (var s = 0; s < 60; s++) _case(s)],
    };
    final file = File(_fixture);
    if (Platform.environment['UPDATE_SLM_PARITY'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent(' ').convert(now)}\n',
        );
    }
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(now['system_prompt'], saved['system_prompt']);
    final cases = saved['cases']! as List<Object?>;
    for (var i = 0; i < cases.length; i++) {
      expect(
        (now['cases']! as List)[i],
        cases[i],
        reason: 'case $i: run with UPDATE_SLM_PARITY=1 and copy the file',
      );
    }
    // The answer schema's words are the ones the model is taught.
    expect(
      slmSystemPrompt,
      contains(SlmChart.values.map((c) => c.name).join('|')),
    );
  });
}
