import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/database_providers.dart';
import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/spaces_providers.dart';

/// "Which space?": shown after unlocking when the app is set to ask.
class ChooseSpaceScreen extends ConsumerWidget {
  const ChooseSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final spaces = ref.watch(spacesProvider);

    Future<void> open(Space space) async {
      final router = GoRouter.of(context);
      await ref.read(activeSpaceIdProvider.notifier).switchTo(space.id);
      ref.read(spaceQuestionProvider.notifier).answered();
      router.go(AppRoutes.home);
    }

    final list = spaces.value;
    if (list != null && list.length < 2) {
      // Only Personal: nothing to ask.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) unawaited(open(list.first));
      });
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
          children: [
            Text('Which space?', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Each one keeps its own accounts, plan and data.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            for (final space in list ?? const <Space>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    key: Key('choose-${space.id}'),
                    minVerticalPadding: 14,
                    leading: CircleAvatar(child: Text(space.initial)),
                    title: Text(space.name),
                    subtitle: Text(
                      space.kind == SpaceKind.personal
                          ? 'Your own money'
                          : space.kind.label,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(space),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Change this in Your spaces › Open the app in.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
