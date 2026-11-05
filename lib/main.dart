import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/data/database/connection.dart';
import 'src/data/database/database_providers.dart';
import 'src/domain/spaces/space.dart';
import 'src/features/look/application/look_providers.dart';
import 'src/features/security/data/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final choice = await readOpenSpaceChoice();
  final spaceId = spaceToOpen(choice, await readActiveSpaceId());
  // Read before the first frame so the lock screen already has the look.
  final look = await readStartupLook(FlutterSecureStore());
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
