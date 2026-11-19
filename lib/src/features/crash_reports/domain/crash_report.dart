import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// A crash report, exactly as it would be sent (ADR 0024).
///
/// It is built field by field from fixed sources, never by cleaning up a
/// string: the build's own values, the system's major version, the chip, the
/// kind of error from a fixed list, and the stack reduced to code offsets (or,
/// in an unobfuscated build, function names and `package:`/`dart:`
/// locations). Never the error's message or `toString()`, which can hold
/// message text, amounts or names. The server checks the same schema again.
class CrashReport {
  const CrashReport({
    required this.app,
    required this.buildNumber,
    required this.build,
    required this.os,
    required this.cpu,
    required this.error,
    required this.buildId,
    required this.stack,
  });

  /// Reads a report saved by [toJson], checking every field again; null when
  /// anything is off.
  static CrashReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final stack = json['stack'];
    final report = CrashReport(
      app: json['app'] is String ? json['app'] as String : '',
      buildNumber: json['build_number'] is int
          ? json['build_number'] as int
          : -1,
      build: json['build'] is String ? json['build'] as String : '',
      os: json['os'] is String ? json['os'] as String : '',
      cpu: json['cpu'] is String ? json['cpu'] as String : '',
      error: json['error'] is String ? json['error'] as String : '',
      buildId: json['build_id'] is String ? json['build_id'] as String : null,
      stack: stack is List
          ? [
              for (final f in stack)
                if (f is String) f,
            ]
          : const [],
    );
    if (json['format'] != format) return null;
    if (stack is! List || report.stack.length != stack.length) return null;
    return report.isValid ? report : null;
  }

  static const format = 1;
  static const maxFrames = 64;
  static const maxBytes = 16 * 1024;

  /// The error types a report may name; anything else is `Other`.
  static const errorTypes = [
    'TypeError',
    'StateError',
    'RangeError',
    'ArgumentError',
    'FormatException',
    'SqliteException',
    'TimeoutException',
    'FileSystemException',
    'PlatformException',
    'Other',
  ];
  static const cpus = ['arm64', 'arm', 'x64', 'ia32', 'riscv64'];
  static const builds = ['play', 'foss', 'ios', 'website'];

  static final _version = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z.-]+)?$',
  );
  static final _os = RegExp(r'^(?:Android|iOS) \d{1,3}$');
  static final _buildId = RegExp(r'^[0-9a-f]{16,64}$');

  /// A frame from an obfuscated release: its offset in the app's code.
  static final offsetFrame = RegExp(r'^#\d{2} pc 0x[0-9a-f]{1,16}$');

  static const _name = r'(?:[A-Za-z_$][A-Za-z0-9_$]{0,79}|<anonymous closure>)';

  /// A frame from an unobfuscated build: a dotted function name and a
  /// location in a package or the Dart SDK. Never a `file:` path.
  static final sourceFrame = RegExp(
    '^#\\d{2} (?:new )?$_name(?:\\.$_name){0,5} '
    r'\((?:package:[a-z0-9_]+/[A-Za-z0-9_/.-]{1,160}\.dart|dart:[a-z_]{1,32}'
    r'(?:/[A-Za-z0-9_/.-]{1,160}\.dart)?)(?::\d{1,6}){0,2}\)$',
  );

  static bool isFrame(String frame) =>
      frame.length <= 240 &&
      (offsetFrame.hasMatch(frame) || sourceFrame.hasMatch(frame));

  /// The app's version, such as `0.5.2`.
  final String app;
  final int buildNumber;

  /// `play`, `foss`, `ios` or `website`.
  final String build;

  /// `Android 13` or `iOS 17`.
  final String os;

  /// `arm64`, `arm`, `x64`, `ia32` or `riscv64`.
  final String cpu;

  /// One of [errorTypes].
  final String error;

  /// The ELF build id from the stack's header, in an obfuscated build.
  final String? buildId;
  final List<String> stack;

  bool get isValid =>
      _version.hasMatch(app) &&
      app.length <= 64 &&
      buildNumber >= 0 &&
      buildNumber <= 2147483647 &&
      builds.contains(build) &&
      _os.hasMatch(os) &&
      cpus.contains(cpu) &&
      errorTypes.contains(error) &&
      (buildId == null || _buildId.hasMatch(buildId!)) &&
      stack.length <= maxFrames &&
      stack.every(isFrame) &&
      utf8.encode(jsonEncode(toJson())).length <= maxBytes;

  /// The report in the schema's field order: what the sheet shows and what
  /// is sent, byte for byte.
  Map<String, Object?> toJson() => {
    'format': format,
    'app': app,
    'build_number': buildNumber,
    'build': build,
    'os': os,
    'cpu': cpu,
    'error': error,
    'build_id': buildId,
    'stack': stack,
  };

  /// The JSON the sheet's "See what will be sent" shows.
  String get preview => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// The kind of error, from the fixed list. [RangeError] is checked before
/// [ArgumentError], which it extends.
String errorTypeOf(Object error) => switch (error) {
  TypeError() => 'TypeError',
  StateError() => 'StateError',
  RangeError() => 'RangeError',
  ArgumentError() => 'ArgumentError',
  FormatException() => 'FormatException',
  SqliteException() => 'SqliteException',
  TimeoutException() => 'TimeoutException',
  FileSystemException() => 'FileSystemException',
  PlatformException() => 'PlatformException',
  _ => 'Other',
};

/// What a report says about the running build and phone.
class CrashContext {
  const CrashContext({
    required this.app,
    required this.buildNumber,
    required this.build,
    required this.os,
    required this.cpu,
  });

  final String app;
  final int buildNumber;
  final String build;
  final String os;
  final String cpu;
}

final _buildIdLine = RegExp(r"^build_id: '([0-9a-f]{16,64})'$");
// "#00 abs 0000007a1c4f8b3c virt 00000000002f4b3c _kDartIsolate...+0x2"
final _obfuscated = RegExp(r'^#(\d{1,3}) +abs [0-9a-f]+ virt ([0-9a-f]+)\b');
// "#0      InsightsController._monthTotals (package:pesaclarity/x.dart:212:7)"
final _symbolic = RegExp(r'^#(\d{1,3}) +(.+?) \(([^()]+)\)$');

/// Reduces [stack] to frames the server accepts: each obfuscated frame to
/// its offset, each unobfuscated one to its function and location, and only
/// from `package:` and `dart:`. Lines that match neither are dropped.
({String? buildId, List<String> frames}) reduceStack(StackTrace stack) {
  String? buildId;
  final frames = <String>[];
  for (final raw in stack.toString().split('\n')) {
    if (frames.length >= CrashReport.maxFrames) break;
    final line = raw.trim();
    final id = _buildIdLine.firstMatch(line);
    if (id != null) {
      buildId = id[1];
      continue;
    }
    final index = frames.length.toString().padLeft(2, '0');
    final offset = _obfuscated.firstMatch(line);
    if (offset != null) {
      final virt = offset[2]!.replaceFirst(RegExp('^0+(?=.)'), '');
      if (virt.length > 16) continue;
      frames.add('#$index pc 0x$virt');
      continue;
    }
    final symbolic = _symbolic.firstMatch(line);
    if (symbolic != null) {
      final frame = '#$index ${symbolic[2]} (${symbolic[3]})';
      if (CrashReport.sourceFrame.hasMatch(frame) && frame.length <= 240) {
        frames.add(frame);
      }
    }
  }
  return (buildId: buildId, frames: frames);
}

/// Builds the report for [error] and [stack], or null when the phone or
/// build cannot be named within the schema.
CrashReport? buildCrashReport(
  Object error,
  StackTrace stack,
  CrashContext context,
) {
  final reduced = reduceStack(stack);
  var frames = reduced.frames;
  CrashReport make() => CrashReport(
    app: context.app,
    buildNumber: context.buildNumber,
    build: context.build,
    os: context.os,
    cpu: context.cpu,
    error: errorTypeOf(error),
    buildId: reduced.buildId,
    stack: frames,
  );
  var report = make();
  while (!report.isValid && frames.isNotEmpty) {
    // Over the size cap: keep the frames nearest the fault.
    frames = frames.sublist(0, frames.length - 1);
    report = make();
  }
  return report.isValid ? report : null;
}
