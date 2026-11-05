import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/tax_repository.dart';
import '../../../domain/books/book_account.dart';
import '../../../domain/books/books.dart';
import '../../../domain/books/business_report.dart' show bookAccountName;
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/tax/tax_estimate.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../books/application/books_providers.dart';
import '../../payees/application/payee_providers.dart';
import '../../spaces/application/business_setup_providers.dart';

/// Where the tax pack sits in the app.
const taxPackAsset = 'assets/tax/tax_pack.json';

/// The tax pack shipped with this app version.
final taxPackProvider = FutureProvider<TaxPack>((ref) async {
  // Read fresh each time: the pack is small, and a cached load would be
  // shared across separate app containers.
  final text = await rootBundle.loadString(taxPackAsset, cache: false);
  return TaxPack.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
});

/// How the open business files, and whether it is VAT registered.
class TaxSettingsController extends AsyncNotifier<TaxSettings> {
  static const settingsKey = 'tax.settings';

  @override
  Future<TaxSettings> build() async => TaxSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(TaxSettings next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final taxSettingsProvider =
    AsyncNotifierProvider<TaxSettingsController, TaxSettings>(
      TaxSettingsController.new,
    );

/// Clients expected to keep back withholding tax, by name in lower case.
class WithholdingClientsController extends AsyncNotifier<Set<String>> {
  static const settingsKey = 'tax.withholdingClients';

  @override
  Future<Set<String>> build() async {
    final json = await ref
        .watch(appSettingsRepositoryProvider)
        .readJson(settingsKey);
    final names = json?['names'];
    return {
      if (names is List)
        for (final n in names) '$n'.toLowerCase(),
    };
  }

  Future<void> expect(String client, {required bool withholds}) async {
    final key = client.trim().toLowerCase();
    final next = {...?state.value};
    withholds ? next.add(key) : next.remove(key);
    await ref.read(appSettingsRepositoryProvider).writeJson(settingsKey, {
      'names': next.toList()..sort(),
    });
    state = AsyncData(next);
  }
}

final withholdingClientsProvider =
    AsyncNotifierProvider<WithholdingClientsController, Set<String>>(
      WithholdingClientsController.new,
    );

/// Money in, costs and tax paid in `[from, to)` from [books]. Tax paid is
/// kept apart from costs, and what clients withheld apart from KRA
/// payments.
TaxFigures taxFigures(
  Books books, {
  required DateTime from,
  required DateTime to,
  required String currency,
  Map<int, String> categoryNames = const {},
}) {
  var income = 0;
  var costs = 0;
  var paid = 0;
  var withheld = 0;
  final byCost = <BookAccount, int>{};
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    for (final l in e.lines) {
      switch (l.account.accountClass) {
        case BookAccountClass.income:
          income -= l.amountMinor;
        case BookAccountClass.expense when l.account == BookAccount.tax:
          if (e.source == JournalSource.withheld) {
            withheld += l.amountMinor;
          } else {
            paid += l.amountMinor;
          }
        case BookAccountClass.expense:
          costs += l.amountMinor;
          byCost[l.account] = (byCost[l.account] ?? 0) + l.amountMinor;
        case _:
          break;
      }
    }
  }
  final largest = byCost.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return TaxFigures(
    incomeMinor: income,
    costsMinor: costs,
    paidToKraMinor: paid,
    withheldMinor: withheld,
    costNames: [
      for (final c in largest.take(3)) bookAccountName(c.key, categoryNames),
    ],
  );
}

/// Everything the Tax screen shows.
class TaxView {
  const TaxView({
    required this.pack,
    required this.settings,
    required this.kind,
    required this.today,
    required this.yearSalesMinor,
    required this.lastMonth,
    required this.thisMonth,
    required this.income,
    required this.withheld,
    this.services = false,
    this.months = const [],
    this.costsCount = 0,
    this.etimsCount = 0,
  });

  final TaxPack pack;

  /// Paid for services, so fees rather than sales.
  final bool services;

  /// The last months, oldest first: estimated against paid.
  final List<MonthTax> months;

  /// Business costs this year, and how many have an eTIMS invoice.
  final int costsCount;
  final int etimsCount;

  /// What the set-aside share of money in this year comes to; null when
  /// it is off.
  int? get setAsideMinor => switch (settings.setAside) {
    null => null,
    final rate => applyRate(income.figures.incomeMinor, rate),
  };

  /// The share to suggest for setting aside.
  BasisPoints get suggestedShare => suggestedSetAside(
    kind: kind,
    pack: pack,
    taxMinor: income.taxMinor,
    incomeMinor: income.figures.incomeMinor,
  );
  final TaxSettings settings;
  final TaxKind kind;
  final CalendarDate today;

  /// Sales over the last 12 months.
  final int yearSalesMinor;

  /// Turnover Tax for last month and this month so far.
  final TurnoverMonth lastMonth;
  final TurnoverMonth thisMonth;

  /// Income tax for the year so far.
  final IncomeTaxEstimate income;

  /// Everything clients withheld this year.
  final List<Withheld> withheld;

  /// Clients whose certificates are still to collect, in order.
  List<String> get certificatesToCollect => [
    ...{
      for (final w in withheld)
        if (w.certificate == null) w.person,
    },
  ];

  /// What may still be owed: the whole estimate's left to pay.
  int get owedMinor => switch (kind) {
    TaxKind.belowTurnover => 0,
    TaxKind.turnover => lastMonth.leftMinor + thisMonth.leftMinor,
    TaxKind.incomeTax => income.leftMinor,
  };
}

final taxViewProvider = FutureProvider<TaxView>((ref) async {
  final pack = await ref.watch(taxPackProvider.future);
  final settings = await ref.watch(taxSettingsProvider.future);
  final books = await ref.watch(booksProvider.future);
  final categories = await ref.watch(categoriesProvider.future);
  final names = {for (final c in categories) c.id: c.name};
  final setup = await ref.watch(businessSetupProvider.future);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final currency = BaseCurrency.code;
  final tomorrow = today.addDays(1).startInstant;

  TaxFigures figures(CalendarDate from, CalendarDate to) => taxFigures(
    books,
    from: from.startInstant,
    to: to.startInstant,
    currency: currency,
    categoryNames: names,
  );

  final year = figures(today.addDays(-365), today.addDays(1));
  final kind = taxKindFor(
    pack: pack,
    yearSalesMinor: year.incomeMinor,
    services: setup.sells == BusinessSells.services,
  );
  final month = today.yearMonth;
  final last = month.previous;
  final paidThisMonth = taxFigures(
    books,
    from: month.firstDay.startInstant,
    to: tomorrow,
    currency: currency,
  ).paidToKraMinor;
  final withheld = [
    for (final w in await ref.watch(taxRepositoryProvider).withheld())
      if (w.at.year == today.year) w,
  ];
  // Month by month: Turnover Tax on each month's sales against what was
  // paid in the month after; income tax as it builds up through the year
  // against what was paid or withheld that month.
  final months = <MonthTax>[];
  for (var i = 5; i >= 0; i--) {
    final m = month.addMonths(-i);
    final f = figures(m.firstDay, m.next.firstDay);
    if (kind == TaxKind.turnover) {
      final paidAfter = i == 0
          ? null
          : figures(m.next.firstDay, m.next.next.firstDay).paidToKraMinor;
      months.add(
        MonthTax(
          month: m,
          estimatedMinor: applyRate(f.incomeMinor, pack.turnoverRate),
          paidMinor: paidAfter,
        ),
      );
    } else if (kind == TaxKind.incomeTax && m.year == today.year) {
      final start = CalendarDate(today.year, 1, 1);
      final through = pack.incomeTax(
        figures(start, m.next.firstDay).profitMinor,
        company: settings.company,
      );
      final before = m.month == 1
          ? 0
          : pack.incomeTax(
              figures(start, m.firstDay).profitMinor,
              company: settings.company,
            );
      months.add(
        MonthTax(
          month: m,
          estimatedMinor: through - before,
          paidMinor: f.paidToKraMinor + f.withheldMinor,
        ),
      );
    }
  }
  // Costs this year, and those with an eTIMS invoice.
  final etims = await ref.watch(taxRepositoryProvider).etimsCosts();
  final yearStart = CalendarDate(today.year, 1, 1).startInstant;
  final costIds = <int>{
    for (final e in books.entries)
      if (e.source == JournalSource.transaction &&
          !e.at.isBefore(yearStart) &&
          e.lines.any(
            (l) =>
                l.account.accountClass == BookAccountClass.expense &&
                l.account != BookAccount.tax &&
                l.account != BookAccount.fees &&
                l.amountMinor > 0,
          ))
        e.sourceId,
  };

  return TaxView(
    months: months,
    costsCount: costIds.length,
    etimsCount: costIds.where(etims.contains).length,
    pack: pack,
    settings: settings,
    kind: kind,
    today: today,
    yearSalesMinor: year.incomeMinor,
    lastMonth: turnoverMonth(
      pack,
      month: last,
      salesMinor: figures(last.firstDay, month.firstDay).incomeMinor,
      paidMinor: paidThisMonth,
    ),
    thisMonth: turnoverMonth(
      pack,
      month: month,
      salesMinor: figures(month.firstDay, today.addDays(1)).incomeMinor,
      paidMinor: 0,
    ),
    income: incomeTaxEstimate(
      pack,
      figures: figures(CalendarDate(today.year, 1, 1), today.addDays(1)),
      settings: settings,
      today: today,
    ),
    withheld: withheld,
    services: setup.sells == BusinessSells.services,
  );
});
