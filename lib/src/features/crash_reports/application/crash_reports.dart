import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/build_info.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/privacy/consent.dart';
import '../../app_status/application/update_links.dart';
import '../../counting/application/counting.dart';
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import '../data/crash_report_sender.dart';
import '../data/pending_crash_store.dart';
import '../domain/crash_report.dart';

/// What to do with a crash report (ADR 0024). The on/off crash report
/// consent becomes this: off is [ask], on is [always].
enum CrashReportChoice {
  /// Show the report on the next start and send it only on Send report:
  /// at once, or without asking again once online. The default.
  ask,

  /// Send it on the next start without asking.
  always,

  /// Delete it without asking.
  never,
}

/// The person's crash report choice, kept with the other privacy settings.
class CrashReportChoiceController extends AsyncNotifier<CrashReportChoice> {
  static const settingsKey = 'privacy.crashReports';

  @override
  Future<CrashReportChoice> build() async {
    final saved = await ref
        .read(mainSettingsRepositoryProvider)
        .readJson(settingsKey);
    final name = saved?['value'];
    for (final choice in CrashReportChoice.values) {
      if (choice.name == name) return choice;
    }
    // Not chosen yet: carry over the old switch.
    final consent = await ref.read(consentControllerProvider.future);
    return consent.valueOf(ConsentKind.crashReports)
        ? CrashReportChoice.always
        : CrashReportChoice.ask;
  }

  Future<void> choose(CrashReportChoice choice) async {
    await ref.read(mainSettingsRepositoryProvider).writeJson(settingsKey, {
      'value': choice.name,
      'changedAt': ref.read(clockProvider)().toUtc().toIso8601String(),
    });
    if (choice == CrashReportChoice.never) {
      final store = ref.read(pendingCrashStoreProvider);
      await store.clear();
      await store.keepToSend(const []);
    }
    state = AsyncData(choice);
  }
}

final crashReportChoiceProvider =
    AsyncNotifierProvider<CrashReportChoiceController, CrashReportChoice>(
      CrashReportChoiceController.new,
    );

/// The chip, as a report names it; null for one the schema has no name for.
String? cpuName(Abi abi) => switch (abi) {
  Abi.androidArm64 || Abi.iosArm64 || Abi.macosArm64 => 'arm64',
  Abi.androidArm => 'arm',
  Abi.androidX64 || Abi.iosX64 || Abi.macosX64 || Abi.linuxX64 => 'x64',
  Abi.androidIA32 => 'ia32',
  Abi.androidRiscv64 || Abi.linuxRiscv64 => 'riscv64',
  _ => null,
};

/// The system's major version as a report names it, such as `Android 13`:
/// on Android from the platform's release number, on iPhone the first
/// number of the version. Never the build fingerprint.
Future<String?> systemName({
  MethodChannel channel = const MethodChannel('com.pesaclarity.app/device'),
}) async {
  try {
    if (Platform.isAndroid) {
      final release = await channel.invokeMethod<String>('systemVersion');
      if (release == null || !RegExp(r'^\d{1,3}$').hasMatch(release)) {
        return null;
      }
      return 'Android $release';
    }
    if (Platform.isIOS) {
      final major = RegExp(r'\d{1,3}')
          .firstMatch(Platform.operatingSystemVersion)?[0];
      return major == null ? null : 'iOS $major';
    }
  } on Object {
    return null;
  }
  return null;
}

/// The build number Flutter defines from `--build-number`.
const _buildNumber = int.fromEnvironment('FLUTTER_BUILD_NUMBER');

/// What reports say about this build and phone, or null when a field cannot
/// be named (a local build with no version, or an unknown chip), in which
/// case nothing is captured.
final crashContextProvider = FutureProvider<CrashContext?>((ref) async {
  final version = ref.watch(buildVersionProvider).trim();
  final cpu = cpuName(Abi.current());
  final os = await systemName();
  if (version.isEmpty || cpu == null || os == null) return null;
  return CrashContext(
    app: version,
    buildNumber: _buildNumber,
    build: ref.watch(updateChannelProvider).name,
    os: os,
    cpu: cpu,
  );
});

/// Catches uncaught Dart errors, turns each into a report at once (so the
/// error itself is never kept) and saves at most three for the next start.
class CrashCapture {
  CrashCapture({required this.store, required this.context});

  final PendingCrashStore store;
  final CrashContext context;

  /// Records [error] and [stack]. Never throws.
  Future<void> record(Object error, StackTrace? stack) async {
    try {
      final report = buildCrashReport(
        error,
        stack ?? StackTrace.empty,
        context,
      );
      if (report != null) await store.add(report);
    } on Object {
      // A failing capture must never make things worse.
    }
  }

  /// Chains onto Flutter's error hooks, keeping the ones already set.
  void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.silent) unawaited(record(details.exception, details.stack));
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousPlatform = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(record(error, stack));
      return previousPlatform?.call(error, stack) ?? false;
    };
  }
}

/// What happened to the reports waiting from the last run.
enum PendingOutcome { none, sent, deleted, waitingForAnswer, notYet }

/// On start: first sends the reports the person already chose to send
/// (Send report while offline). Then, with Never send, deletes waiting
/// reports; with Always send, sends them (at most three) once the person
/// has agreed to a policy that describes crash reports (2.4 or later);
/// with Ask each time, leaves them for the sheet that asks.
Future<PendingOutcome> handlePendingCrashReports(Ref ref) async {
  final store = ref.read(pendingCrashStoreProvider);
  final chosen = await sendChosenCrashReports(
    store,
    ref.read(crashReportSenderProvider),
  );
  final pending = await store.read();
  if (pending.isEmpty) return chosen;
  final choice = await ref.read(crashReportChoiceProvider.future);
  switch (choice) {
    case CrashReportChoice.never:
      await store.clear();
      return PendingOutcome.deleted;
    case CrashReportChoice.ask:
      return PendingOutcome.waitingForAnswer;
    case CrashReportChoice.always:
      break;
  }
  final policy = await ref.read(privacyPolicyProvider.future);
  final consent = await ref.read(consentControllerProvider.future);
  final accepted = consent.acceptedVersion;
  if (accepted == null ||
      reportingPolicyVersion.isNewerThan(accepted) ||
      consent.needsReview(policy)) {
    return PendingOutcome.notYet;
  }
  final sender = ref.read(crashReportSenderProvider);
  if (sender == null) return PendingOutcome.notYet;
  return sendCrashReports(store, sender, pending);
}

/// Sends [reports] and forgets them once the server has taken each. Ones
/// that could not be sent (offline) stay for the next start.
Future<PendingOutcome> sendCrashReports(
  PendingCrashStore store,
  CrashReportSender sender,
  List<CrashReport> reports,
) async {
  final left = await _send(sender, reports);
  await store.clear();
  for (final report in left) {
    await store.add(report);
  }
  return left.isEmpty ? PendingOutcome.sent : PendingOutcome.notYet;
}

/// Send report: sends [reports] now, and keeps the ones that cannot go
/// yet (offline, or a build without a server) to go without asking again.
Future<PendingOutcome> sendCrashReportsAsChosen(
  PendingCrashStore store,
  CrashReportSender? sender,
  List<CrashReport> reports,
) async {
  final left = sender == null ? reports : await _send(sender, reports);
  await store.clear();
  if (left.isNotEmpty) {
    await store.keepToSend([...await store.readToSend(), ...left]);
  }
  return left.isEmpty ? PendingOutcome.sent : PendingOutcome.notYet;
}

/// Sends the reports the person chose to send that waited for a
/// connection; quietly keeps them while still offline.
Future<PendingOutcome> sendChosenCrashReports(
  PendingCrashStore store,
  CrashReportSender? sender,
) async {
  final waiting = await store.readToSend();
  if (waiting.isEmpty) return PendingOutcome.none;
  if (sender == null) return PendingOutcome.notYet;
  final left = await _send(sender, waiting);
  await store.keepToSend(left);
  return left.isEmpty ? PendingOutcome.sent : PendingOutcome.notYet;
}

Future<List<CrashReport>> _send(
  CrashReportSender sender,
  List<CrashReport> reports,
) async => [
  for (final report in reports.take(PendingCrashStore.maxPending))
    if (!await sender.send(report)) report,
];

/// Runs [handlePendingCrashReports] once per start.
final pendingCrashReportsProvider = FutureProvider<PendingOutcome>(
  handlePendingCrashReports,
);
