import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/lifecycle/app_resumed.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
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
/// [clock]. The app never goes to the background and back, since there is
/// no widgets binding to tell it.
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
      appResumedProvider.overrideWithValue(const Stream.empty()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The app's own providers as they run on a phone: every space in its own
/// SQLCipher file in a temporary folder, opened by the real
/// `personalDatabaseProvider` and `appDatabaseProvider`, with the database
/// key released. Returns the container and that folder, which holds
/// everything the app keeps (`kept/` too).
Future<(ProviderContainer, Directory)> spacesOnFiles({
  required DateTime Function() clock,
  SmsSource? sms,
  List<Override> overrides = const [],
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp('spaces_on_files');
  // Where the phone would keep the app's files.
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(paths, (call) async => dir.path);
  final container = ProviderContainer(
    overrides: [
      smsSourceProvider.overrideWithValue(sms ?? FakeSmsSource()),
      smsParseBatchProvider.overrideWithValue(
        (packs, messages) async => parseAll(packs, messages),
      ),
      clockProvider.overrideWithValue(clock),
      ...overrides,
    ],
  );
  container.read(releasedDatabaseKeyProvider).release(generateDatabaseKey());
  addTearDown(() async {
    container.dispose();
    // The databases close in the background once their providers go.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    messenger.setMockMethodCallHandler(paths, null);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
  return (container, dir);
}

/// Waits until [done] is true, for a few seconds at most.
Future<void> until(Future<bool> Function() done, {int tries = 300}) async {
  for (var i = 0; i < tries; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Lets background work, such as sorting a payment just read, finish.
Future<void> settle([int milliseconds = 400]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Waits until the live capture has stopped restarting and listens to
/// [phone], as it does a moment after the app opens or the space changes.
Future<void> captureIsSteady(PhoneInbox phone) async {
  var seen = -1;
  var steady = 0;
  await until(() async {
    final now = phone.listenedSenders.length;
    steady = now == seen && now > 0 ? steady + 1 : 0;
    seen = now;
    return steady >= 30;
  }, tries: 600);
}

/// Runs [body] and returns the errors nothing caught, such as those of work
/// a provider left running when it was rebuilt, so a test can still assert
/// on the records.
Future<List<Object>> guarded(Future<void> Function() body) async {
  final stray = <Object>[];
  final done = Completer<void>();
  unawaited(
    runZonedGuarded(() async {
      try {
        await body();
        if (!done.isCompleted) done.complete();
      } on Object catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }
    }, (error, stack) => stray.add(error)),
  );
  await done.future;
  return stray;
}
