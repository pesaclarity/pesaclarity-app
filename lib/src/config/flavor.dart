import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Distribution channel the app was built for, matching the Android product flavours.
enum AppFlavor {
  /// Google Play build. May use Google services (Sign-In, Play Integrity) later.
  play,

  /// F-Droid build. Must never depend on Google services.
  foss;

  /// Resolves the flavour from the `--flavor` the app was built with.
  ///
  /// Unknown or missing values fall back to [foss], the more restrictive build.
  static AppFlavor fromName(String? name) => switch (name) {
    'play' => AppFlavor.play,
    _ => AppFlavor.foss,
  };

  /// Whether code paths that need Google services may run.
  bool get allowsGoogleServices => this == AppFlavor.play;
}

/// The flavour of the running build.
final appFlavorProvider = Provider<AppFlavor>(
  (ref) => AppFlavor.fromName(appFlavor),
);
