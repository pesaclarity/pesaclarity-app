import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/perf/startup_timeline.dart';

void main() {
  tearDown(StartupTimeline.reset);

  test('marks nothing until main starts the clock', () {
    StartupTimeline.mark('first frame');
    expect(StartupTimeline.phases, isEmpty);
    expect(StartupTimeline.waitsFor('first frame'), isFalse);
  });

  test('marks each phase once, in order, with time since main', () {
    StartupTimeline.start();
    expect(StartupTimeline.waitsFor('first frame'), isTrue);
    StartupTimeline.mark('first frame');
    StartupTimeline.mark('first frame');
    StartupTimeline.mark('home data shown');
    expect(StartupTimeline.phases.map((p) => p.$1), [
      'main',
      'first frame',
      'home data shown',
    ]);
    expect(StartupTimeline.waitsFor('first frame'), isFalse);
    final times = StartupTimeline.phases.map((p) => p.$2).toList();
    expect(times, orderedEquals([...times]..sort()));
  });
}
