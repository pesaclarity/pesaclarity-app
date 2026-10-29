import 'dart:async';

import 'package:pesaclarity/src/domain/time/calendar.dart';

/// Every test runs with East Africa Time as the user's timezone, so dates
/// come out the same on any machine, whatever its own zone.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  UserTimeZone.set(nairobiUtcOffset);
  await testMain();
}
