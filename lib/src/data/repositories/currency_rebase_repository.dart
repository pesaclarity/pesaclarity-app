import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart' show minorUnitDigits;
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Moves the amounts the person typed in one base currency to another.
abstract interface class CurrencyRebaseRepository {
  /// Converts the plan (repeating and one-off items, month snapshots),
  /// goals, debts and their instalments, money lent and its repayments, and
  /// subscriptions held in [from] into [to], where one [from] unit buys
  /// [rate] of [to]. Transactions and accounts keep their own currency and
  /// are converted as they are read.
  Future<void> rebase({
    required String from,
    required String to,
    required double rate,
  });
}

class DriftCurrencyRebaseRepository implements CurrencyRebaseRepository {
  DriftCurrencyRebaseRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> rebase({
    required String from,
    required String to,
    required double rate,
  }) => _db.transaction(() async {
    final scale = _scale(from, to, rate);
    Future<void> run(String sql, [List<Object?> args = const []]) =>
        _db.customStatement(sql, args);
    String converted(String column) =>
        '$column = CAST(ROUND($column * ?) AS INTEGER)';

    // Tables without a currency column hold base amounts.
    await run('UPDATE recurring SET ${converted('amount_minor')}', [scale]);
    await run('UPDATE budget_items SET ${converted('amount_minor')}', [scale]);
    await run(
      'UPDATE budget_snapshots SET ${converted('planned_minor')}, '
      '${converted('actual_minor')}',
      [scale, scale],
    );

    await run(
      'UPDATE debt_instalments SET ${converted('amount_minor')} '
      'WHERE debt_id IN (SELECT id FROM debts WHERE currency = ?)',
      [scale, from],
    );
    await run(
      'UPDATE debts SET ${converted('starting_balance_minor')}, '
      '${converted('minimum_payment_minor')}, '
      '${converted('planned_payment_minor')}, ${converted('balance_minor')}, '
      'currency = ? WHERE currency = ?',
      [scale, scale, scale, scale, to, from],
    );
    await run(
      'UPDATE goals SET ${converted('target_minor')}, '
      '${converted('saved_minor')}, currency = ? WHERE currency = ?',
      [scale, scale, to, from],
    );
    await run(
      'UPDATE loan_payments SET ${converted('amount_minor')} '
      'WHERE lent_loan_id IN (SELECT id FROM lent_loans WHERE currency = ?)',
      [scale, from],
    );
    await run(
      'UPDATE lent_loans SET ${converted('amount_minor')}, currency = ? '
      'WHERE currency = ?',
      [scale, to, from],
    );
    await run(
      'UPDATE subscriptions SET ${converted('amount_minor')}, currency = ? '
      'WHERE currency = ?',
      [scale, to, from],
    );
  });

  /// Multiplier from [from] minor units to [to] minor units.
  static double _scale(String from, String to, double rate) {
    var scale = rate;
    final digits = minorUnitDigits(to) - minorUnitDigits(from);
    for (var i = 0; i < digits.abs(); i++) {
      scale = digits > 0 ? scale * 10 : scale / 10;
    }
    return scale;
  }
}

final currencyRebaseRepositoryProvider = Provider<CurrencyRebaseRepository>(
  (ref) => DriftCurrencyRebaseRepository(ref.watch(appDatabaseProvider)),
);
