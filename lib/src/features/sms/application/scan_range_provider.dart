import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/sms_scan_marks_repository.dart';
import '../domain/scan_range.dart';

/// The period messages are read from, chosen in My accounts. Every message
/// until the person picks otherwise.
class ScanRangeController extends AsyncNotifier<ScanRange> {
  static const settingsKey = 'sms.scan_range';

  @override
  Future<ScanRange> build() async => ScanRange.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  /// Saves [range]. When it changes, every account is read again from the
  /// new start on the next scan; messages already read are skipped.
  Future<void> choose(ScanRange range) async {
    if (range == state.value) return;
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, range.toJson());
    await ref.read(smsScanMarksRepositoryProvider).clearAll();
    state = AsyncData(range);
  }
}

final scanRangeProvider = AsyncNotifierProvider<ScanRangeController, ScanRange>(
  ScanRangeController.new,
);
