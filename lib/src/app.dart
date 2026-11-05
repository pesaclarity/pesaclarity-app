import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/look/look_settings.dart';
import 'features/categoriser/presentation/learn_when_due.dart';
import 'features/look/application/look_providers.dart';
import 'features/look/presentation/field_style_theme.dart';
import 'features/security/presentation/lock_screen.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget.
class PesaClarityApp extends ConsumerWidget {
  const PesaClarityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The chosen theme is read once the app is unlocked and set up; until
    // then, and by default, it follows the phone.
    final open = ref.watch(launchGateProvider).value ?? false;
    final theme = open
        ? ref.watch(lookSettingsProvider).value?.theme ?? ThemeChoice.system
        : ThemeChoice.system;
    return MaterialApp.router(
      title: 'Pesa Clarity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeModeFor(theme),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => AppLockGate(
        child: LearnWhenDue(child: FieldStyleTheme(child: child!)),
      ),
    );
  }
}
