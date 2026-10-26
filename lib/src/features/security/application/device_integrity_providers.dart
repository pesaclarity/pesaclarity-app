import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../data/device_integrity_checker.dart';
import '../data/device_warning_repository.dart';
import '../domain/device_integrity.dart';

final deviceIntegrityCheckerProvider = Provider<DeviceIntegrityChecker>(
  (ref) => const MethodChannelDeviceIntegrityChecker(),
);

final deviceWarningRepositoryProvider = Provider<DeviceWarningRepository>(
  (ref) => DriftDeviceWarningRepository(ref.watch(appDatabaseProvider)),
);

/// The integrity check result, run once per app session.
final deviceIntegrityReportProvider = FutureProvider<DeviceIntegrityReport>(
  (ref) => ref.watch(deviceIntegrityCheckerProvider).check(),
);

/// Whether to show the modified-phone warning: something was found and the
/// person has not dismissed it yet.
final showDeviceWarningProvider = FutureProvider<bool>((ref) async {
  final report = await ref.watch(deviceIntegrityReportProvider.future);
  if (!report.looksModified) return false;
  return !await ref.watch(deviceWarningRepositoryProvider).isDismissed();
});
