import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An event each time the app comes back to the front: from the background,
/// or from behind a system dialog. Override in tests with a stream the test
/// adds to.
final appResumedProvider = Provider<Stream<void>>((ref) {
  final resumed = StreamController<void>.broadcast();
  final listener = AppLifecycleListener(onResume: () => resumed.add(null));
  ref.onDispose(() {
    listener.dispose();
    unawaited(resumed.close());
  });
  return resumed.stream;
});
