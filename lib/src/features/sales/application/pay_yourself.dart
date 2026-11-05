import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/category_seeds.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/sales/sale_matching.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/time/calendar.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import 'sales_providers.dart';

/// How Personal files pay from the owner's business.
enum PersonalPayAs {
  salary('Salary from my business'),
  other('Other income');

  const PersonalPayAs(this.label);

  final String label;

  CategorySeed get seed => switch (this) {
    PersonalPayAs.salary => payFromBusinessSeed,
    PersonalPayAs.other => defaultCategories.firstWhere(
      (c) => c.key == 'business_income',
    ),
  };
}

/// Personal setting holding pay from a business still to meet its message.
const expectedPayKey = 'business.payYourself.expected';

/// Pay from a business that Personal is waiting to see come in.
class ExpectedPay {
  const ExpectedPay({
    required this.amountMinor,
    required this.at,
    required this.method,
    required this.categoryKey,
    required this.business,
  });

  final int amountMinor;
  final DateTime at;
  final SalePaymentMethod method;
  final String categoryKey;
  final String business;

  Map<String, Object?> toJson() => {
    'amountMinor': amountMinor,
    'atMs': at.millisecondsSinceEpoch,
    'method': method.name,
    'categoryKey': categoryKey,
    'business': business,
  };

  static ExpectedPay? fromJson(Object? json) {
    if (json is! Map) return null;
    final amount = json['amountMinor'];
    final at = json['atMs'];
    final method = SalePaymentMethod.values
        .where((m) => m.name == json['method'])
        .firstOrNull;
    final key = json['categoryKey'];
    final business = json['business'];
    if (amount is! int ||
        at is! int ||
        method == null ||
        key is! String ||
        business is! String) {
      return null;
    }
    return ExpectedPay(
      amountMinor: amount,
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      method: method,
      categoryKey: key,
      business: business,
    );
  }
}

Future<List<ExpectedPay>> _expected(AppSettingsRepository settings) async {
  final list = (await settings.readJson(expectedPayKey))?['items'];
  return [
    if (list is List)
      for (final item in list) ?ExpectedPay.fromJson(item),
  ];
}

Future<void> _saveExpected(
  AppSettingsRepository settings,
  List<ExpectedPay> items,
) => settings.writeJson(expectedPayKey, {
  'items': [for (final i in items) i.toJson()],
});

/// Pay yourself: money leaves the business as the owner's pay and comes
/// into Personal as income.
class PayYourselfController {
  PayYourselfController(this._ref);

  final Ref _ref;

  /// The business pays the owner [amountMinor] by [method]; Personal files
  /// it [as] chosen. Cash shows in Personal at once; M-Pesa and bank wait
  /// for their messages on both sides.
  Future<void> payYourself({
    required int amountMinor,
    required SalePaymentMethod method,
    required PersonalPayAs as,
  }) async {
    final now = _ref.read(clockProvider)();
    final business = _ref.read(activeSpaceProvider).name;
    final db = _ref.read(appDatabaseProvider);
    await _ref
        .read(quickRecordsRepositoryProvider)
        .paidYourself(
          at: now,
          amountMinor: amountMinor,
          method: method,
          categoryId: await ensureCategory(db, ownerPaySeed),
          cashAccountId: await _ref
              .read(accountsRepositoryProvider)
              .cashAccount(
                name: cashAccountName,
                openingDate: CalendarDate.local(now).startInstant,
              ),
        );
    await _ref.read(salesControllerProvider).matchWaiting();

    final personal = _ref.read(personalDatabaseProvider);
    if (method == SalePaymentMethod.cash) {
      final account = await DriftAccountsRepository(personal).cashAccount(
        name: cashAccountName,
        openingDate: CalendarDate.local(now).startInstant,
      );
      await personal
          .into(personal.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: now,
              amountMinor: amountMinor,
              direction: TransactionDirection.inflow,
              currency: Value(BaseCurrency.code),
              source: TransactionSource.manual,
              counterpartyName: Value(business),
              categoryOverrideId: Value(
                await ensureCategory(personal, as.seed),
              ),
            ),
          );
      return;
    }
    final settings = _ref.read(mainSettingsRepositoryProvider);
    await _saveExpected(settings, [
      ...await _expected(settings),
      ExpectedPay(
        amountMinor: amountMinor,
        at: now,
        method: method,
        categoryKey: as.seed.key,
        business: business,
      ),
    ]);
  }

  /// In Personal: files pay from a business when its message has come in,
  /// and returns how many were filed.
  Future<int> matchInPersonal() async {
    final settings = _ref.read(mainSettingsRepositoryProvider);
    final expected = await _expected(settings);
    if (expected.isEmpty) return 0;
    final personal = _ref.read(personalDatabaseProvider);
    final seeds = {for (final a in PersonalPayAs.values) a.seed.key: a.seed};
    final waiting = [
      for (final (i, e) in expected.indexed)
        WaitingPayment(
          id: i,
          kind: WaitingKind.payFromBusiness,
          method: e.method,
          amountMinor: e.amountMinor,
          currency: BaseCurrency.code,
          at: e.at,
          categoryId: await ensureCategory(
            personal,
            seeds[e.categoryKey] ?? payFromBusinessSeed,
          ),
        ),
    ];
    final from = waiting
        .map((w) => w.at)
        .reduce((a, b) => a.isBefore(b) ? a : b)
        .subtract(saleMatchWindow);
    final to = waiting
        .map((w) => w.at)
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(saleMatchWindow);
    final entries = await DriftTransactionsRepository(personal)
        .ledgerEntries(from: from, to: to);
    final accounts = {
      for (final a in await DriftAccountsRepository(personal).openings())
        a.id: a.type,
    };
    final matches = matchWaitingPayments(
      waiting,
      entries,
      accountTypes: accounts,
      linked: const {},
    );
    if (matches.isEmpty) return 0;
    for (final MapEntry(key: w, value: transactionId) in matches.entries) {
      await (personal.update(
        personal.transactions,
      )..where((t) => t.id.equals(transactionId))).write(
        TransactionsCompanion(categoryOverrideId: Value(w.categoryId)),
      );
    }
    final done = {for (final w in matches.keys) w.id};
    await _saveExpected(settings, [
      for (final (i, e) in expected.indexed)
        if (!done.contains(i)) e,
    ]);
    return matches.length;
  }
}

final payYourselfControllerProvider = Provider<PayYourselfController>(
  PayYourselfController.new,
);

/// While Personal is open, files pay from a business as its message comes.
final personalPayMatcherProvider = Provider<void>((ref) {
  if (ref.watch(activeSpaceProvider).kind != SpaceKind.personal) return;
  ref.listen(ledgerChangesProvider, (_, _) async {
    try {
      await ref.read(payYourselfControllerProvider).matchInPersonal();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Filing pay from a business failed: $error');
    }
  }, fireImmediately: true);
});
