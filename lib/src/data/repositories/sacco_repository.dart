import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'sacco_links.dart';

/// A SACCO's loan as the person types it.
class SaccoLoanInput {
  const SaccoLoanInput({
    required this.owedMinor,
    required this.monthlyMinor,
    this.rateBasisPoints,
    this.checkOff = true,
    this.checkOffDay,
  });

  final int owedMinor;
  final int monthlyMinor;
  final int? rateBasisPoints;

  /// Repaid by check-off from salary; otherwise by the SACCO's paybill.
  final bool checkOff;

  /// The payday the check-off is taken on, as a day of the month.
  final int? checkOffDay;
}

/// SACCO accounts: one account each, holding deposits, shares and a loan.
class SaccoRepository {
  SaccoRepository(this._db);

  final AppDatabase _db;

  /// Adds a SACCO from what its statement shows on [at]: its deposits and
  /// shares start the account's balance, and its loan, if any, joins
  /// Debts. Payments to its paybill from [at] on become moves to it.
  Future<int> add({
    required String name,
    required String currency,
    required int depositsMinor,
    required int sharesMinor,
    required DateTime at,
    String? paybill,
    int? contributionMinor,
    int? borrowTimesTenths,
    SaccoLoanInput? loan,
  }) async {
    final id = await _db.transaction(() async {
      final accountId = await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: name.trim(),
              type: AccountType.sacco,
              currency: Value(currency),
              openingBalanceMinor: Value(depositsMinor + sharesMinor),
              openingDate: at,
            ),
          );
      await _db
          .into(_db.saccoDetails)
          .insert(
            SaccoDetailsCompanion.insert(
              accountId: Value(accountId),
              paybill: Value(saccoPaybill(paybill)),
              sharesMinor: Value(sharesMinor),
              contributionMinor: Value(contributionMinor),
              borrowTimesTenths: Value(borrowTimesTenths),
            ),
          );
      if (loan != null) {
        await _setLoan(accountId, name.trim(), currency, loan, at);
      }
      return accountId;
    });
    await syncSaccos(_db);
    await takeCheckOffs(_db, CalendarDate.local(at));
    return id;
  }

  /// Changes a SACCO's details. Its deposits stay as they are: changing
  /// [sharesMinor] moves the account's balance by the difference.
  Future<void> update(
    int accountId, {
    required String name,
    String? paybill,
    required int sharesMinor,
    int? contributionMinor,
    int? borrowTimesTenths,
  }) async {
    await _db.transaction(() async {
      final account = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingle();
      final details = await saccoDetailsOf(_db, accountId);
      final oldShares = details?.sharesMinor ?? 0;
      await (_db.update(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(
          name: Value(name.trim()),
          openingBalanceMinor: Value(
            account.openingBalanceMinor + sharesMinor - oldShares,
          ),
        ),
      );
      await _db
          .into(_db.saccoDetails)
          .insertOnConflictUpdate(
            SaccoDetailsCompanion(
              accountId: Value(accountId),
              paybill: Value(saccoPaybill(paybill)),
              sharesMinor: Value(sharesMinor),
              contributionMinor: Value(contributionMinor),
              borrowTimesTenths: Value(borrowTimesTenths),
              loanDebtId: Value(details?.loanDebtId),
              checkOff: Value(details?.checkOff ?? false),
              checkOffDay: Value(details?.checkOffDay),
              checkOffFrom: Value(details?.checkOffFrom),
            ),
          );
      // Its loan keeps its name.
      if (details?.loanDebtId case final debtId?) {
        await (_db.update(_db.debts)..where(
              (d) =>
                  d.id.equals(debtId) & d.lender.equals('${account.name} loan'),
            ))
            .write(DebtsCompanion(lender: Value('${name.trim()} loan')));
      }
    });
    await syncSaccos(_db);
  }

  /// Sets or changes the SACCO's loan as owed on [at].
  Future<void> setLoan(int accountId, SaccoLoanInput loan, DateTime at) async {
    await _db.transaction(() async {
      final account = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingle();
      await _setLoan(accountId, account.name, account.currency, loan, at);
    });
    await syncSaccos(_db);
    await takeCheckOffs(_db, CalendarDate.local(at));
  }

  Future<void> _setLoan(
    int accountId,
    String name,
    String currency,
    SaccoLoanInput loan,
    DateTime at,
  ) async {
    final details = await saccoDetailsOf(_db, accountId);
    var debtId = details?.loanDebtId;
    if (debtId == null) {
      debtId = await _db
          .into(_db.debts)
          .insert(
            DebtsCompanion.insert(
              lender: '$name loan',
              type: DebtType.saccoLoan,
              currency: Value(currency),
              startingBalanceMinor: loan.owedMinor,
              annualRateBasisPoints: Value(loan.rateBasisPoints),
              minimumPaymentMinor: Value(loan.monthlyMinor),
              balanceMinor: Value(loan.owedMinor),
              balanceAsOf: Value(at),
            ),
          );
    } else {
      await (_db.update(_db.debts)..where((d) => d.id.equals(debtId!))).write(
        DebtsCompanion(
          annualRateBasisPoints: Value(loan.rateBasisPoints),
          minimumPaymentMinor: Value(loan.monthlyMinor),
          balanceMinor: Value(loan.owedMinor),
          balanceAsOf: Value(at),
        ),
      );
    }
    await (_db.update(
      _db.saccoDetails,
    )..where((s) => s.accountId.equals(accountId))).write(
      SaccoDetailsCompanion(
        loanDebtId: Value(debtId),
        checkOff: Value(loan.checkOff),
        checkOffDay: Value(loan.checkOff ? loan.checkOffDay : null),
        checkOffFrom: Value(loan.checkOff ? at : null),
      ),
    );
  }

  /// Every SACCO with its details, updating as they change.
  Stream<List<(Account, SaccoDetailsRow)>> watchAll() =>
      (_db.select(_db.accounts).join([
        innerJoin(
          _db.saccoDetails,
          _db.saccoDetails.accountId.equalsExp(_db.accounts.id),
        ),
      ])..orderBy([OrderingTerm.asc(_db.accounts.name)])).watch().map(
        (rows) => [
          for (final r in rows)
            (r.readTable(_db.accounts), r.readTable(_db.saccoDetails)),
        ],
      );

  /// What happened on SACCO [accountId] lately, newest first: deposits,
  /// money taken out, and the loan's repayments, check-offs included.
  Future<List<SaccoActivity>> recent(int accountId, {int limit = 5}) async {
    final details = await saccoDetailsOf(_db, accountId);
    final t = _db.transactions;
    final rows =
        await (_db.select(t)
              ..where((t) => t.accountId.equals(accountId))
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(limit))
            .get();
    final fromNames = {
      for (final a in await _db.select(_db.accounts).get()) a.id: a.name,
    };
    final list = [
      for (final r in rows)
        SaccoActivity(
          at: r.occurredAt,
          signedMinor: r.direction == TransactionDirection.inflow
              ? r.amountMinor
              : -r.amountMinor,
          kind: r.debtId != null
              ? SaccoActivityKind.loanByPaybill
              : r.direction == TransactionDirection.inflow
              ? SaccoActivityKind.deposit
              : SaccoActivityKind.takenOut,
          from: fromNames[r.transferAccountId],
          ownTransfer: r.transferPairId != null,
        ),
    ];
    if (details?.loanDebtId case final debtId? when details!.checkOff) {
      for (final p
          in await (_db.select(_db.loanPayments)
                ..where((p) => p.debtId.equals(debtId))
                ..orderBy([(p) => OrderingTerm.desc(p.paidOn)])
                ..limit(limit))
              .get()) {
        list.add(
          SaccoActivity(
            at: p.paidOn,
            signedMinor: -p.amountMinor,
            kind: SaccoActivityKind.checkOff,
          ),
        );
      }
    }
    list.sort((a, b) => b.at.compareTo(a.at));
    return list.take(limit).toList();
  }
}

enum SaccoActivityKind { deposit, takenOut, loanByPaybill, checkOff }

/// One line of a SACCO's recent activity.
class SaccoActivity {
  const SaccoActivity({
    required this.at,
    required this.signedMinor,
    required this.kind,
    this.from,
    this.ownTransfer = false,
  });

  final DateTime at;
  final int signedMinor;
  final SaccoActivityKind kind;

  /// The account a deposit came from.
  final String? from;
  final bool ownTransfer;
}

final saccoRepositoryProvider = Provider<SaccoRepository>(
  (ref) => SaccoRepository(ref.watch(appDatabaseProvider)),
);
