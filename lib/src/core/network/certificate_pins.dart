import 'dart:convert';

/// Certificate pins set at build time, for example:
///
/// ```sh
/// --dart-define=PESACLARITY_CERT_PINS="api.pesaclarity.org=sha256/AAA...=,sha256/BBB...=;fl.pesaclarity.org=..."
/// ```
///
/// Each pin is the base64 SHA-256 of a certificate's SubjectPublicKeyInfo,
/// the same value OkHttp and Android's network security config use.
const certificatePinsDefine = String.fromEnvironment('PESACLARITY_CERT_PINS');

/// SPKI SHA-256 pins per host.
///
/// Three states: none configured (development builds before the server is
/// deployed), a valid set, or an invalid set. Pinned clients treat an invalid
/// set as "refuse every connection", so a typo can never turn pinning off.
class CertificatePins {
  const CertificatePins._(this._byHost, this.error);

  /// Builds pins from a map of host to base64 pins, validating each entry.
  factory CertificatePins.of(Map<String, Iterable<String>> byHost) {
    final result = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in byHost.entries) {
      final host = key.trim().toLowerCase();
      if (host.isEmpty || host.contains(RegExp(r'[\s/:]'))) {
        return CertificatePins._({}, 'Invalid pinned host "$key"');
      }
      final pins = <String>{};
      for (final raw in value) {
        final pin = _normalisePin(raw);
        if (pin == null) {
          return CertificatePins._({}, 'Invalid pin for $host');
        }
        pins.add(pin);
      }
      if (pins.length < minPinsPerHost) {
        return CertificatePins._(
          {},
          '$host needs at least $minPinsPerHost distinct pins',
        );
      }
      result[host] = Set.unmodifiable(pins);
    }
    return CertificatePins._(Map.unmodifiable(result), null);
  }

  /// Parses `host=pin,pin;host=pin,pin`. Blank input means [none].
  factory CertificatePins.parse(String raw) {
    if (raw.trim().isEmpty) return none;
    final byHost = <String, List<String>>{};
    for (final entry in raw.split(';')) {
      if (entry.trim().isEmpty) continue;
      final at = entry.indexOf('=');
      if (at <= 0) {
        return const CertificatePins._({}, 'Expected host=pin,pin');
      }
      final host = entry.substring(0, at).trim().toLowerCase();
      // Pins themselves end in '=' padding, so split only on the first one.
      byHost
          .putIfAbsent(host, () => [])
          .addAll(entry.substring(at + 1).split(',').map((p) => p.trim()));
    }
    if (byHost.isEmpty) return none;
    return CertificatePins.of(byHost);
  }

  /// Pins from the `PESACLARITY_CERT_PINS` build define.
  factory CertificatePins.fromEnvironment() =>
      CertificatePins.parse(certificatePinsDefine);

  /// No pins: clients use the platform's normal certificate checks only.
  static const none = CertificatePins._({}, null);

  /// Each host needs a current pin and at least one backup, so the server's
  /// key can rotate without locking out installed apps.
  static const minPinsPerHost = 2;

  final Map<String, Set<String>> _byHost;

  /// Why the configuration was rejected, or null when it is valid.
  final String? error;

  /// Whether any pins (valid or not) were configured.
  bool get isConfigured => _byHost.isNotEmpty || error != null;

  /// The hosts that have pins.
  Iterable<String> get hosts => _byHost.keys;

  /// The pins for [host], or null when it has none.
  Set<String>? forHost(String host) => _byHost[host.toLowerCase()];

  static String? _normalisePin(String raw) {
    var value = raw.trim();
    if (value.startsWith('sha256/')) value = value.substring(7);
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? base64.encode(bytes) : null;
    } on FormatException {
      return null;
    }
  }
}
