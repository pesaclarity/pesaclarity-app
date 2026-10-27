import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/currency_rebase_repository.dart';
import '../data/rates_client.dart';

/// The phone's region, such as `KE`, from its language settings.
final deviceRegionProvider = Provider<String?>(
  (ref) => PlatformDispatcher.instance.locale.countryCode,
);

/// How long fetched rates stay fresh.
const ratesMaxAge = Duration(hours: 12);

@immutable
class CurrencySettings {
  const CurrencySettings({
    required this.base,
    this.chosen = false,
    this.ownRates = const {},
    this.rates,
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

  CurrencyConverter get converter =>
      CurrencyConverter(base: base, rates: rates, ownRates: ownRates);

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

  @override
  Future<CurrencySettings> build() async {
    final json = await _settings.readJson(settingsKey);
    final saved = await _settings.readJson(ratesKey);
    final rates = saved == null ? null : ExchangeRates.fromSaved(saved);
    final base = json?['base'];
    final own = json?['ownRates'];
    return CurrencySettings(
      // Amounts saved before a currency was chosen are in KES, so that stays
      // the base until the person picks one; setup suggests their region's.
      base: base is String && isKnownCurrency(base) ? base : 'KES',
      chosen: json?['chosen'] == true,
      ownRates: {
        if (own is Map)
          for (final MapEntry(:key, :value) in own.entries)
            if (key is String && value is num && value > 0)
              key: value.toDouble(),
      },
      rates: rates,
    );
  }

  Future<CurrencySettings> _current() async => state.value ?? await future;

  Future<void> _save(CurrencySettings next) async {
    await _settings.writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }

  /// Saves [code] as chosen during setup, when nothing is counted yet.
  Future<void> choose(String code) async {
    final current = await _current();
    await _save(
      CurrencySettings(
        base: code,
        chosen: true,
        ownRates: _rebaseOwn(current, code),
        rates: current.rates,
      ),
    );
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
      final latest = await _current();
      state = AsyncData(
        CurrencySettings(
          base: latest.base,
          chosen: latest.chosen,
          ownRates: latest.ownRates,
          rates: rates,
        ),
      );
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
  );
});

/// Fetches rates once the settings are read, when they are stale. The app
/// shell keeps it alive.
final ratesRefreshProvider = FutureProvider<bool>((ref) async {
  await ref.watch(currencyControllerProvider.future);
  if (!ref.watch(ratesConfiguredProvider)) return false;
  return ref.read(currencyControllerProvider.notifier).refreshRates();
});
