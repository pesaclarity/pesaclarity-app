import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// How far the app has got since `main` started, for measuring startup on
/// a real phone (see tool/startup_timing.sh).
///
/// Each phase is marked once: on the Dart timeline, where DevTools'
/// Performance view and `flutter run --profile --trace-startup` show it,
/// and as a log line `Startup: <phase> <ms> ms`. Release builds mark
/// nothing, and neither do tests, which never call [start].
abstract final class StartupTimeline {
  static final _clock = Stopwatch();
  static final _marked = <String>{};
  static final _phases = <(String, int)>[];

  /// The phases marked so far, with milliseconds since [start].
  static List<(String, int)> get phases => List.unmodifiable(_phases);

  /// Starts the clock. `main` calls this first.
  static void start() {
    if (kReleaseMode || _clock.isRunning) return;
    _clock.start();
    mark('main');
  }

  /// Whether [phase] is still to be marked: false once it is, and always
  /// in release builds and tests.
  static bool waitsFor(String phase) =>
      !kReleaseMode && _clock.isRunning && !_marked.contains(phase);

  /// Marks [phase] the first time it is reached; later calls do nothing.
  static void mark(String phase) {
    if (kReleaseMode || !_clock.isRunning || !_marked.add(phase)) return;
    final ms = _clock.elapsedMilliseconds;
    _phases.add((phase, ms));
    developer.Timeline.instantSync('startup: $phase', arguments: {'ms': '$ms'});
    debugPrint('Startup: $phase $ms ms');
  }

  /// Forgets every mark and stops the clock, for tests.
  @visibleForTesting
  static void reset() {
    _clock
      ..stop()
      ..reset();
    _marked.clear();
    _phases.clear();
  }
}
