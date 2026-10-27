import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/network/pinned_http_client.dart';
import '../../../core/time/clock.dart';

/// The public exchange-rates address, set at build time with
/// `--dart-define=PESACLARITY_RATES_URL=https://.../latest/{base}`, where
/// `{base}` stands for the base currency code. Without it the app uses only
/// rates the person sets.
const ratesUrlDefine = String.fromEnvironment('PESACLARITY_RATES_URL');

/// The rates address for [base] from [template], or null when the template
/// is missing or not https.
Uri? ratesUrl(String template, String base) {
  if (!template.contains('{base}')) return null;
  final uri = Uri.tryParse(template.replaceAll('{base}', base));
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  return uri;
}

/// Fetches today's exchange rates. The request carries only the base
/// currency code; nothing about the person.
abstract interface class RatesClient {
  /// Null when no rates service is configured.
  Future<ExchangeRates?> fetch(String base);
}

class HttpRatesClient implements RatesClient {
  HttpRatesClient({
    required this.template,
    required this._client,
    required this._now,
  });

  final String template;
  final http.Client _client;
  final DateTime Function() _now;

  @override
  Future<ExchangeRates?> fetch(String base) async {
    final url = ratesUrl(template, base);
    if (url == null) return null;
    final response = await _client
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('Rates returned ${response.statusCode}', url);
    }
    final rates = ExchangeRates.fromJson(
      jsonDecode(response.body),
      fetchedAt: _now(),
    );
    if (rates == null) throw http.ClientException('Rates were unreadable', url);
    return rates;
  }
}

/// The rates service is a third party whose certificates we do not choose,
/// so it uses the platform's checks rather than our pinning.
final ratesClientProvider = Provider<RatesClient>(
  (ref) => HttpRatesClient(
    template: ratesUrlDefine,
    client: IOClient(ref.watch(httpClientFactoryProvider).createUnpinned()),
    now: ref.watch(clockProvider),
  ),
);

/// Whether this build can fetch rates.
final ratesConfiguredProvider = Provider<bool>(
  (ref) => ratesUrl(ratesUrlDefine, 'USD') != null,
);
