import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pesaclarity/src/features/sharing/application/group_sync_controller.dart';

/// Group sync showing [view], for screens: nothing reaches a server.
class FixedGroupSync extends GroupSyncController {
  FixedGroupSync(this.view, {this.turnOnResult = TurnOnResult.on});

  final GroupSyncView view;
  final TurnOnResult turnOnResult;
  int syncs = 0;
  int turnOns = 0;

  @override
  Future<GroupSyncView> build() async => view;

  @override
  Future<void> sync() async => syncs++;

  @override
  Future<TurnOnResult> turnOn() async {
    turnOns++;
    return turnOnResult;
  }

  @override
  Future<void> turnOff() async {}
}

/// The build's sync switch on, showing [sync].
List<Override> groupSyncOverrides(FixedGroupSync sync) => [
  groupSyncFlagProvider.overrideWithValue(true),
  groupSyncProvider.overrideWith(() => sync),
];
