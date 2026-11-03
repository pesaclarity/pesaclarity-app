import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/data/database/connection.dart';
import 'src/data/database/database_providers.dart';
import 'src/domain/spaces/space.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final choice = await readOpenSpaceChoice();
  final spaceId = spaceToOpen(choice, await readActiveSpaceId());
  runApp(
    ProviderScope(
      overrides: [
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(spaceId)),
        openSpaceChoiceProvider.overrideWith(() => OpenSpaceChoice(choice)),
        spaceQuestionProvider.overrideWith(
          () => SpaceQuestion(choice == askForSpace),
        ),
      ],
      child: const PesaClarityApp(),
    ),
  );
}
