import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/currency_rebase_repository.dart';
import '../../../data/repositories/rate_history_repository.dart';
import '../../../domain/time/calendar.dart';
import '../data/rates_client.dart';

/// The phone's region, such as `KE`, from its language settings.
final deviceRegionProvider = Provider<String?>(
  (ref) => PlatformDispatcher.instance.locale.countryCode,
);

/// How long setup waits for the saved currency settings before it saves
/// the choice over the defaults.
const choiceWait = Duration(seconds: 2);

/// How long fetched rates stay fresh.
const ratesMaxAge = Duration(hours: 12);

@immutable
class CurrencySettings {
  const CurrencySettings({
    required this.base,
    this.chosen = false,
    this.ownRates = const {},
    this.rates,
    this.history,
  });

  /// The currency the person counts in.
  final String base;

  /// Whether the person picked [base], rather than it coming from the
  /// phone's region.
  final bool chosen;

  /// Rates the person set: one [base] unit buys that much of a currency.
  final Map<String, double> ownRates;

  /// The latest fetched rates, in whatever base the service used.
  final ExchangeRates? rates;

  /// The first rates fetched each day, so amounts convert at their day's.
  final RateHistory? history;

  CurrencyConverter get converter => CurrencyConverter(
    base: base,
    rates: rates,
    ownRates: ownRates,
    history: history,
  );

  CurrencySettings copyWith({
    String? base,
    bool? chosen,
    Map<String, double>? ownRates,
    ExchangeRates? rates,
    RateHistory? history,
  }) => CurrencySettings(
    base: base ?? this.base,
    chosen: chosen ?? this.chosen,
    ownRates: ownRates ?? this.ownRates,
    rates: rates ?? this.rates,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => {
    'base': base,
    'chosen': chosen,
    'ownRates': ownRates,
  };
}

/// The base currency, the person's own rates and the latest fetched rates.
class CurrencyController extends AsyncNotifier<CurrencySettings> {
  static const settingsKey = 'currency.settings';
  static const ratesKey = 'currency.rates';

  AppSettingsRepository get _settings =>
      ref.read(appSettingsRepositoryProvider);

  RateHistoryRepository get _history => ref.read(rateHistoryRepositoryProvider);

  @override
  Future<CurrencySettings> build() async {
    final json = await _settings.readJson(settingsKey);
    final saved = await _settings.readJson(ratesKey);
    final rates = saved == null ? null : ExchangeRates.fromSaved(saved);
    var history = await _history.read();
    // Rates fetched before rates were kept by day become their day's.
    if (history.isEmpty && rates != null) {
      await _history.keep(CalendarDate.local(rates.fetchedAt), rates);
      history = await _history.read();
    }
    return settingsFrom(json, rates: rates, history: history);
  }

  /// The settings saved as [json] (null before any are), with [rates] and
  /// [history].
  static CurrencySettings settingsFrom(
    Map<String, Object?>? json, {
    ExchangeRates? rates,
    RateHistory? history,
  }) {
    final base = json?['base'];
    final own = json?['ownRates'];
    // Amounts saved before a currency was chosen are in KES, so that stays
    // the base until the person picks one; setup suggests their region's.
    final code = base is String && isKnownCurrency(base)
        ? base
        : BaseCurrency.code;
    return CurrencySettings(
      base: code,
      chosen: json?['chosen'] == true,
      ownRates: {
        if (own is Map)
          for (final MapEntry(:key, :value) in own.entries)
            if (key is String && value is num && value > 0)
              key: value.toDouble(),
      },
      rates: rates,
      history: history,
    );
  }

  /// The converter [db]'s saved settings and kept rates make, read straight
  /// from the space's database rather than from this controller, so work
  /// that runs without the app's providers (pairing own transfers, posting
  /// the journal) converts as the app does. Read again only when
  /// [storedRatesSignature] changes. Changes nothing.
  static Future<CurrencyConverter> storedConverter(AppDatabase db) async {
    final signature = await storedRatesSignature(db);
    final cached = _stored[db];
    if (cached != null && cached.$1 == signature) return cached.$2;
    final converter = await _readStoredConverter(db);
    _stored[db] = (signature, converter);
    return converter;
  }

  static final _stored = Expando<(String, CurrencyConverter)>();

  /// What changes when [storedConverter] would convert differently: how
  /// many days of rates are kept and the latest day, the saved settings
  /// (base currency and the person's own rates), and the latest rates
  /// while no day's are kept. Rates are only ever added to a day that had
  /// none, so these change whenever they do.
  static Future<String> storedRatesSignature(AppDatabase db) async {
    final kept = await db
        .customSelect(
          'SELECT COUNT(*) AS n, MAX(day) AS last FROM rate_snapshots',
          readsFrom: {db.rateSnapshots},
        )
        .getSingle();
    final n = kept.read<int>('n');
    Future<String> setting(String key) async =>
        (await (db.select(
          db.appSettings,
        )..where((s) => s.key.equals(key))).getSingleOrNull())?.value ??
        '';
    final saved = await setting(settingsKey);
    return '$n|${kept.readNullable<String>('last') ?? ''}|'
        // With nothing saved, the base is the app's default.
        '${saved.isEmpty ? BaseCurrency.code : saved}|'
        '${n == 0 ? await setting(ratesKey) : ''}';
  }

  static Future<CurrencyConverter> _readStoredConverter(AppDatabase db) async {
    final settings = DriftAppSettingsRepository(db);
    final saved = await settings.readJson(ratesKey);
    final rates = saved == null ? null : ExchangeRates.fromSaved(saved);
    var history = await DriftRateHistoryRepository(db).read();
    // Rates fetched before rates were kept by day count as their day's.
    if (history.isEmpty && rates != null) {
      history = RateHistory([
        DayRates(CalendarDate.local(rates.fetchedAt), rates),
      ]);
    }
    return settingsFrom(
      await settings.readJson(settingsKey),
      rates: rates,
      history: history,
    ).converter;
  }

  Future<CurrencySettings> _current() async => state.value ?? await future;

  Future<void> _save(CurrencySettings next) async {
    await _settings.writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }

  /// Saves [code] as chosen during setup, when nothing is counted yet.
  ///
  /// It waits at most [choiceWait] for the saved settings: on a new phone
  /// there are none, so when they are slow or cannot be read it starts from
  /// the defaults and only the write has to work. A failed write throws, and
  /// nothing changes.
  Future<void> choose(String code) async {
    var current = state.value;
    var stillLoading = false;
    if (current == null) {
      try {
        current = await future.timeout(choiceWait);
      } on TimeoutException {
        stillLoading = true;
      } on Object {
        // Unreadable: the defaults, as on a new phone.
      }
    }
    final from = current ?? settingsFrom(null);
    final next = CurrencySettings(
      base: code,
      chosen: true,
      ownRates: _rebaseOwn(from, code),
      rates: from.rates,
      history: from.history,
    );
    await _settings.writeJson(settingsKey, next.toJson());
    if (stillLoading) {
      // The read still under way would bring back what was there before:
      // read again, which finds what was just saved.
      ref.invalidateSelf();
    } else {
      state = AsyncData(next);
    }
  }

  /// Switches the base currency, converting the plan, goals, debts, loans
  /// and subscriptions typed in the old one at today's rate. Returns false,
  /// changing nothing, when there is no rate between the two.
  Future<bool> switchTo(String code) async {
    final current = await _current();
    if (code == current.base) return true;
    final rate = current.converter.rateFor(code);
    if (rate == null) return false;
    await ref
        .read(currencyRebaseRepositoryProvider)
        .rebase(from: current.base, to: code, rate: rate);
    await _save(
      CurrencySettings(
        base: code,
        chosen: true,
        ownRates: _rebaseOwn(current, code),
        rates: current.rates,
        history: current.history,
      ),
    );
    return true;
  }

  /// Sets the person's own rate for [code] (one base unit buys [rate]), or
  /// clears it with null.
  Future<void> setOwnRate(String code, double? rate) async {
    final current = await _current();
    await _save(
      CurrencySettings(
        base: current.base,
        chosen: current.chosen,
        ownRates: {
          for (final e in current.ownRates.entries)
            if (e.key != code) e.key: e.value,
          if (rate != null && rate > 0) code: rate,
        },
        rates: current.rates,
        history: current.history,
      ),
    );
  }

  /// Fetches rates when they are older than [ratesMaxAge], or always with
  /// [force]. Returns whether rates are fresh afterwards; a failed fetch
  /// keeps the last rates.
  Future<bool> refreshRates({bool force = false}) async {
    final current = await _current();
    final now = ref.read(clockProvider)();
    final fetched = current.rates?.fetchedAt;
    if (!force && fetched != null && now.difference(fetched) < ratesMaxAge) {
      return true;
    }
    try {
      final rates = await ref.read(ratesClientProvider).fetch(current.base);
      if (rates == null) return false;
      await _settings.writeJson(ratesKey, rates.toJson());
      await _history.keep(CalendarDate.local(rates.fetchedAt), rates);
      final history = await _history.read();
      final latest = await _current();
      state = AsyncData(latest.copyWith(rates: rates, history: history));
      return true;
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Rates did not load: $error');
      return false;
    }
  }

  /// Own rates moved to a new base: a rate to the new base itself is
  /// dropped, and the rest are expressed per new base unit.
  static Map<String, double> _rebaseOwn(CurrencySettings s, String to) {
    final toRate = s.converter.rateFor(to);
    if (toRate == null) return const {};
    return {
      for (final e in s.ownRates.entries)
        if (e.key != to) e.key: e.value / toRate,
    };
  }
}

final currencyControllerProvider =
    AsyncNotifierProvider<CurrencyController, CurrencySettings>(
      CurrencyController.new,
    );

/// The base currency. Reading it also sets [BaseCurrency.code], so amounts
/// made without a currency are in it.
final baseCurrencyProvider = Provider<String>((ref) {
  final code =
      ref.watch(currencyControllerProvider).value?.base ?? BaseCurrency.code;
  BaseCurrency.code = code;
  return code;
});

/// Converts amounts into the base currency.
final currencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final base = ref.watch(baseCurrencyProvider);
  final settings = ref.watch(currencyControllerProvider).value;
  return CurrencyConverter(
    base: base,
    rates: settings?.rates,
    ownRates: settings?.ownRates ?? const {},
    history: settings?.history,
  );
});

/// Fetches rates once the settings are read, when they are stale. The app
/// shell keeps it alive.
final ratesRefreshProvider = FutureProvider<bool>((ref) async {
  await ref.watch(currencyControllerProvider.future);
  if (!ref.watch(ratesConfiguredProvider)) return false;
  return ref.read(currencyControllerProvider.notifier).refreshRates();
});
