import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/categoriser/presentation/learn_when_due.dart';
import 'features/look/application/look_providers.dart';
import 'features/look/presentation/field_style_theme.dart';
import 'features/security/presentation/lock_screen.dart';
import 'routing/app_router.dart';
import 'shared/widgets/amounts_hidden.dart';
import 'theme/app_theme.dart';

/// Root widget.
class PesaClarityApp extends ConsumerWidget {
  const PesaClarityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // From the first frame: the copy read at startup until the saved look
    // is read after unlock. The usual is to follow the phone.
    final theme = ref.watch(currentLookProvider).theme;
    return MaterialApp.router(
      title: 'Pesa Clarity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeModeFor(theme),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => AmountsHiddenScope(
        child: FieldStyleTheme(
          child: AppLockGate(child: LearnWhenDue(child: child!)),
        ),
      ),
    );
  }
}
