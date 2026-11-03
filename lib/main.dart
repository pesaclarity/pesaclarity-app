import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/data/database/connection.dart';
import 'src/data/database/database_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final spaceId = await readActiveSpaceId();
  runApp(
    ProviderScope(
      overrides: [
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(spaceId)),
      ],
      child: const PesaClarityApp(),
    ),
  );
}
