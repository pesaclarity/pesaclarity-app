import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Distribution channel the app was built for: the Android product flavours,
/// and the App Store for iPhone.
enum AppFlavor {
  /// Google Play build. May use Google services (Sign-In, Play Integrity).
  play,

  /// F-Droid build. Must never depend on Google services.
  foss,

  /// iPhone build. Uses no Google services.
  appstore;

  /// Resolves the flavour from the `--flavor` the app was built with, or
  /// from the [platform] for iPhone builds, which have no flavours.
  ///
  /// Unknown or missing values fall back to [foss], the more restrictive build.
  static AppFlavor fromName(String? name, {TargetPlatform? platform}) =>
      switch (name) {
        'play' => AppFlavor.play,
        'appstore' => AppFlavor.appstore,
        _ when platform == TargetPlatform.iOS => AppFlavor.appstore,
        _ => AppFlavor.foss,
      };

  /// Whether code paths that need Google services may run.
  bool get allowsGoogleServices => this == AppFlavor.play;
}

/// The flavour of the running build.
final appFlavorProvider = Provider<AppFlavor>(
  (ref) => AppFlavor.fromName(appFlavor, platform: defaultTargetPlatform),
);
