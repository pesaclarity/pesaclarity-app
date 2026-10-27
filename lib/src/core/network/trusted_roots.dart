import 'dart:convert';
import 'dart:io';

/// Our servers, which may only use the [trustedRootsDefine] authorities:
///
/// ```sh
/// --dart-define=PESACLARITY_PINNED_HOSTS=api.pesaclarity.org,vault.pesaclarity.org
/// ```
const pinnedHostsDefine = String.fromEnvironment('PESACLARITY_PINNED_HOSTS');

/// The root certificates our servers' chains may end in, as comma-separated
/// base64 DER, for example from
/// `openssl x509 -in root.pem -outform der | base64 -w0`.
const trustedRootsDefine = String.fromEnvironment('PESACLARITY_TRUSTED_ROOTS');

/// Which certificate authorities our servers may use.
///
/// Our hosts' certificates are managed by the hosting providers and renewed
/// with new keys every few months, so the app pins the root authorities
/// instead of the keys: connections to a pinned host succeed only when its
/// chain ends in one of these roots.
///
/// Three states: none configured (development builds before the server is
/// deployed), a valid set, or an invalid set. Clients refuse every connection
/// on an invalid set, so a typo can never turn pinning off.
class TrustedRoots {
  const TrustedRoots._(this._hosts, this._roots, this.error);

  /// Builds the set from [hosts] and [rootsDer], validating each.
  factory TrustedRoots.of(
    Iterable<String> hosts,
    Iterable<List<int>> rootsDer,
  ) {
    final hostSet = <String>{};
    for (final raw in hosts) {
      final host = raw.trim().toLowerCase();
      if (host.isEmpty || host.contains(RegExp(r'[\s/:=]'))) {
        return TrustedRoots._(const {}, const [], 'Invalid pinned host "$raw"');
      }
      hostSet.add(host);
    }
    final roots = <String, List<int>>{};
    for (final der in rootsDer) {
      roots[base64.encode(der)] = der;
    }
    if (hostSet.isEmpty && roots.isEmpty) return none;
    if (hostSet.isEmpty) {
      return const TrustedRoots._({}, [], 'Trusted roots set without hosts');
    }
    if (roots.length < minRoots) {
      return const TrustedRoots._(
        {},
        [],
        'At least $minRoots distinct trusted roots are needed',
      );
    }
    for (final der in roots.values) {
      try {
        SecurityContext().setTrustedCertificatesBytes(utf8.encode(_pem(der)));
      } on TlsException {
        return const TrustedRoots._(
          {},
          [],
          'A trusted root is not a certificate',
        );
      }
    }
    return TrustedRoots._(
      Set.unmodifiable(hostSet),
      List.unmodifiable(roots.values),
      null,
    );
  }

  /// Parses comma-separated hosts and comma-separated base64 DER roots.
  factory TrustedRoots.parse({required String hosts, required String roots}) {
    final rootsDer = <List<int>>[];
    for (final raw in roots.split(',')) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      try {
        rootsDer.add(base64.decode(value));
      } on FormatException {
        return const TrustedRoots._({}, [], 'A trusted root is not base64');
      }
    }
    return TrustedRoots.of([
      for (final host in hosts.split(','))
        if (host.trim().isNotEmpty) host,
    ], rootsDer);
  }

  /// From the `PESACLARITY_PINNED_HOSTS` and `PESACLARITY_TRUSTED_ROOTS`
  /// build defines.
  factory TrustedRoots.fromEnvironment() =>
      TrustedRoots.parse(hosts: pinnedHostsDefine, roots: trustedRootsDefine);

  /// No pinning: clients use the platform's certificate authorities.
  static const none = TrustedRoots._({}, [], null);

  /// A current root and at least one other, so a provider can move to
  /// another authority without locking out installed apps.
  static const minRoots = 2;

  final Set<String> _hosts;
  final List<List<int>> _roots;

  /// Why the configuration was rejected, or null when it is valid.
  final String? error;

  /// Whether pinning was configured (validly or not).
  bool get isConfigured => _hosts.isNotEmpty || error != null;

  /// Whether connections to [host] must chain to the trusted roots.
  bool isPinned(String host) => _hosts.contains(host.toLowerCase());

  /// The hosts that are pinned.
  Iterable<String> get hosts => _hosts;

  /// A TLS context that trusts only these roots, not the platform's.
  SecurityContext securityContext() {
    final context = SecurityContext();
    for (final der in _roots) {
      context.setTrustedCertificatesBytes(utf8.encode(_pem(der)));
    }
    return context;
  }

  static String _pem(List<int> der) {
    final body = base64.encode(der);
    final lines = [
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, i + 64 > body.length ? body.length : i + 64),
    ];
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
        '-----END CERTIFICATE-----\n';
  }
}
