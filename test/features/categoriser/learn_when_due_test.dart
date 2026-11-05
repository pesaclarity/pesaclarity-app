import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/presentation/learn_when_due.dart';
import 'package:pesaclarity/src/routing/app_router.dart';

class _Gate extends Notifier<AsyncValue<bool>> {
  @override
  AsyncValue<bool> build() => const AsyncLoading();

  void set(AsyncValue<bool> value) => state = value;
}

final _gate = NotifierProvider<_Gate, AsyncValue<bool>>(_Gate.new);

void main() {
  testWidgets('reads nothing until the app is unlocked and set up', (
    tester,
  ) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        launchGateProvider.overrideWith((ref) => ref.watch(_gate)),
        learningScheduleProvider.overrideWith((ref) async {
          reads++;
          return null as LearningSchedule?;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LearnWhenDue(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(reads, 0, reason: 'locked');

    container.read(_gate.notifier).set(const AsyncData(false));
    await tester.pump();
    expect(reads, 0, reason: 'still onboarding');

    container.read(_gate.notifier).set(const AsyncData(true));
    await tester.pump();
    expect(reads, 1);
  });
}
