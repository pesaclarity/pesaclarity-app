import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/database_providers.dart';
import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/spaces_providers.dart';

/// Lists the spaces on this phone; tapping one opens it.
Future<void> showSpaces(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const SpacesSheet(),
);

class SpacesSheet extends ConsumerWidget {
  const SpacesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final activeId = ref.watch(activeSpaceIdProvider);

    Future<void> open(Space space) async {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      await ref.read(activeSpaceIdProvider.notifier).switchTo(space.id);
      router.go(AppRoutes.home);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your spaces', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Each space keeps its own accounts, plan and data.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final (i, space) in spaces.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      key: Key('space-${space.id}'),
                      leading: CircleAvatar(
                        backgroundColor: space.id == activeId
                            ? theme.colorScheme.primary
                            : colors.border,
                        foregroundColor: space.id == activeId
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        child: Text(space.initial),
                      ),
                      title: Text(space.name),
                      subtitle: space.name == space.kind.label
                          ? null
                          : Text(space.kind.label),
                      trailing: space.id == activeId
                          ? Icon(
                              Icons.check,
                              color: theme.colorScheme.primary,
                              semanticLabel: 'Open now',
                            )
                          : null,
                      onTap: () => open(space),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (spaces.length > 1) ...[
              Card(
                child: ListTile(
                  key: const Key('spaces-open-in'),
                  title: const Text('Open the app in'),
                  subtitle: Text(
                    openChoiceLabel(ref.watch(openSpaceChoiceProvider), spaces),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showOpenSpaceChoice(context),
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              key: const Key('spaces-add'),
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.addSpace);
              },
              child: const Text('Add a space'),
            ),
          ],
        ),
      ),
    );
  }
}

/// How [choice] reads: `The last space you used`, `Ask each time` or a
/// space's name.
String openChoiceLabel(String choice, List<Space> spaces) => switch (choice) {
  openLastSpace => 'The last space you used',
  askForSpace => 'Ask each time',
  _ =>
    spaces.where((s) => s.id == choice).map((s) => s.name).firstOrNull ??
        'The last space you used',
};

/// Which space the app opens in after unlocking.
Future<void> showOpenSpaceChoice(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const OpenSpaceSheet(),
    );

class OpenSpaceSheet extends ConsumerWidget {
  const OpenSpaceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final choice = ref.watch(openSpaceChoiceProvider);
    final lastName = ref.watch(activeSpaceProvider).name;
    final options = <(String, String, String?)>[
      (openLastSpace, 'The last space you used', '$lastName right now'),
      for (final s in spaces) (s.id, s.name, null),
      (askForSpace, 'Ask each time', 'Choose a space when the app opens'),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Open the app in', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Which space you see first after unlocking.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: RadioGroup<String>(
                groupValue: choice,
                onChanged: (v) async {
                  if (v == null) return;
                  await ref.read(openSpaceChoiceProvider.notifier).choose(v);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Column(
                  children: [
                    for (final (i, (value, title, hint))
                        in options.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      RadioListTile<String>(
                        key: Key('open-in-$value'),
                        value: value,
                        title: Text(title),
                        subtitle: hint == null ? null : Text(hint),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
