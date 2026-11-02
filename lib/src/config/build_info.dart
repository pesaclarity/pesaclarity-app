import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'flavor.dart';

/// The build's version, such as `0.2.0` for a release or `0.2.0-dev.31` for
/// a test build, set at build time with
/// `--dart-define=PESACLARITY_VERSION=...`. Empty for local builds.
const _version = String.fromEnvironment('PESACLARITY_VERSION');

/// What Profile shows under Build: the version and the flavour, such as
/// `0.2.0-dev.31 · play`, or the flavour alone when no version is set.
String buildLabel(String version, AppFlavor flavor) {
  final trimmed = version.trim();
  return trimmed.isEmpty ? flavor.name : '$trimmed · ${flavor.name}';
}

/// The version of the running build, or empty when none was set.
final buildVersionProvider = Provider<String>((ref) => _version);
