import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';

import 'fake_sms_source.dart';

/// Keeps the open space and where the app opens in memory only.
class NoActiveSpaceStore implements ActiveSpaceStore {
  const NoActiveSpaceStore();

  @override
  Future<void> write(String spaceId) async {}

  @override
  Future<void> writeOpenChoice(String choice) async {}
}

/// The app's own providers over two in-memory databases: [personal] and one
/// [other] space, switched with the real `activeSpaceIdProvider`. Messages
/// come from [sms] (an empty inbox when not given) and the time from
/// [clock].
ProviderContainer twoSpaces({
  required AppDatabase personal,
  required AppDatabase other,
  required DateTime Function() clock,
  SmsSource? sms,
  String active = personalSpaceId,
}) {
  final container = ProviderContainer(
    overrides: [
      activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(active)),
      activeSpaceStoreProvider.overrideWithValue(const NoActiveSpaceStore()),
      personalDatabaseProvider.overrideWithValue(personal),
      appDatabaseProvider.overrideWith(
        (ref) => ref.watch(activeSpaceIdProvider) == personalSpaceId
            ? personal
            : other,
      ),
      smsSourceProvider.overrideWithValue(sms ?? FakeSmsSource()),
      smsParseBatchProvider.overrideWithValue(
        (packs, messages) async => parseAll(packs, messages),
      ),
      clockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
