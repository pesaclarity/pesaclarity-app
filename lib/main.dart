import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/perf/startup_timeline.dart';
import 'src/data/database/connection.dart';
import 'src/data/database/database_providers.dart';
import 'src/domain/spaces/space.dart';
import 'src/features/look/application/look_providers.dart';
import 'src/features/security/data/secure_store.dart';

Future<void> main() async {
  StartupTimeline.start();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // The space to open and the look, read before the first frame so the
  // lock screen already has the look. Each waits on the platform (files
  // and the keystore), so the three are read at once.
  final (choice, lastSpace, look) = await (
    readOpenSpaceChoice(),
    readActiveSpaceId(),
    readStartupLook(FlutterSecureStore()),
  ).wait;
  final spaceId = spaceToOpen(choice, lastSpace);
  StartupTimeline.mark('look read');
  unawaited(
    binding.waitUntilFirstFrameRasterized.then(
      (_) => StartupTimeline.mark('first frame'),
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(spaceId)),
        openSpaceChoiceProvider.overrideWith(() => OpenSpaceChoice(choice)),
        spaceQuestionProvider.overrideWith(
          () => SpaceQuestion(choice == askForSpace),
        ),
        startupLookProvider.overrideWithValue(look),
      ],
      child: const PesaClarityApp(),
    ),
  );
}
