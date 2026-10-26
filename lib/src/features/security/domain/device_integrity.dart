/// Signs that the phone is rooted or this build was tampered with.
///
/// These are light checks that a determined user can hide; they drive a
/// warning only and never block use of the app.
class DeviceIntegrityReport {
  const DeviceIntegrityReport({
    this.suBinary = false,
    this.testKeys = false,
    this.debuggableRelease = false,
  });

  /// Reads the platform's answer. [releaseBuild] is whether this Dart code is
  /// a release build; a debuggable flag only matters then.
  factory DeviceIntegrityReport.fromPlatform(
    Map<Object?, Object?> values, {
    required bool releaseBuild,
  }) => DeviceIntegrityReport(
    suBinary: values['suBinary'] == true,
    testKeys: values['testKeys'] == true,
    debuggableRelease: releaseBuild && values['appDebuggable'] == true,
  );

  /// A report with nothing found, also used when the check cannot run.
  static const clean = DeviceIntegrityReport();

  /// An `su` binary or Superuser app is present.
  final bool suBinary;

  /// Android was signed with test keys (a custom or development ROM).
  final bool testKeys;

  /// A release build of the app is marked debuggable, so it was rebuilt.
  final bool debuggableRelease;

  bool get looksModified => suBinary || testKeys || debuggableRelease;
}
