import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/lifecycle/app_resumed.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void go(List<AppLifecycleState> states) =>
      states.forEach(binding.handleAppLifecycleStateChanged);

  setUp(() => go([AppLifecycleState.resumed]));
  tearDown(() => go([AppLifecycleState.resumed]));

  test('fires each time the app comes back to the front', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var times = 0;
    final sub = container.read(appResumedProvider).listen((_) => times++);
    addTearDown(sub.cancel);

    // Already at the front when first listened to.
    await pumpEventQueue();
    expect(times, 0);

    // To the background: nothing until it is back.
    go([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await pumpEventQueue();
    expect(times, 0);
    go([AppLifecycleState.hidden, AppLifecycleState.inactive]);
    await pumpEventQueue();
    expect(times, 0);
    go([AppLifecycleState.resumed]);
    await pumpEventQueue();
    expect(times, 1);

    // Behind a system dialog, such as a permission request, and back.
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await pumpEventQueue();
    expect(times, 2);
  });

  test('stops with its container', () async {
    final container = ProviderContainer();
    var times = 0;
    var done = false;
    container
        .read(appResumedProvider)
        .listen((_) => times++, onDone: () => done = true);

    container.dispose();
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await pumpEventQueue();
    expect(times, 0);
    expect(done, isTrue);
  });
}
