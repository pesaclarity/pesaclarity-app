import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/ask_repository.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/layout.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/ask_providers.dart';
import '../application/ask_settings.dart';
import 'ask_strings.dart';

/// Ask's settings for the open space.
class AskSettingsScreen extends ConsumerWidget {
  const AskSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final space = ref.watch(activeSpaceProvider);
    final settings =
        ref.watch(askSettingsProvider).value ?? const AskSettings();
    final controller = ref.read(askSettingsProvider.notifier);
    final danger = theme.colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text(AskStrings.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Layout.gutter,
          8,
          Layout.gutter,
          Layout.screenBottom,
        ),
        children: [
          GroupedSection(
            children: [
              SwitchListTile.adaptive(
                key: const Key('ask-show'),
                title: const Text(AskStrings.showAsk),
                subtitle: const Text(AskStrings.showAskDetail),
                value: settings.show,
                onChanged: (v) => controller.save(settings.copyWith(show: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('ask-save'),
                title: const Text(AskStrings.saveConversations),
                subtitle: const Text(AskStrings.saveConversationsDetail),
                value: settings.save,
                onChanged: (v) => controller.save(settings.copyWith(save: v)),
              ),
              ListTile(
                title: const Text(AskStrings.keepFor),
                subtitle: const Text(AskStrings.keepForDetail),
                enabled: settings.save,
                trailing: ChoiceMenu<AskKeepFor>(
                  key: const Key('ask-keep-for'),
                  name: AskStrings.keepFor,
                  options: [
                    for (final k in AskKeepFor.values)
                      (k, AskStrings.keepForLabels[k.name]!),
                  ],
                  value: settings.keepFor,
                  itemKey: (k) => Key('ask-keep-${k.name}'),
                  onChanged: (k) async {
                    await controller.save(settings.copyWith(keepFor: k));
                    final keep = k.duration;
                    if (keep != null) {
                      await ref
                          .read(askRepositoryProvider)
                          .purgeBefore(
                            ref.read(clockProvider)().subtract(keep),
                          );
                    }
                  },
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('ask-charts'),
                title: const Text(AskStrings.chartsInAnswers),
                subtitle: const Text(AskStrings.chartsDetail),
                value: settings.charts,
                onChanged: (v) => controller.save(settings.copyWith(charts: v)),
              ),
            ],
          ),
          const SizedBox(height: Layout.cardGap),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('ask-conversations-row'),
                title: const Text(AskStrings.conversations),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.askConversations),
              ),
            ],
          ),
          const SizedBox(height: Layout.cardGap),
          GroupedSection(
            footer:
                '${AskStrings.keepFor}: '
                '${AskStrings.keepForLabels.values.join(', ')}. '
                '${AskStrings.settingsFootnote}',
            children: [
              ListTile(
                key: const Key('ask-delete-all'),
                title: Text(
                  AskStrings.deleteAll,
                  style: TextStyle(color: danger),
                ),
                subtitle: Text(AskStrings.deleteAllDetail(space.name)),
                onTap: () async {
                  final sure = await confirmDelete(
                    context,
                    title: AskStrings.deleteAllQuestion,
                    body: AskStrings.deleteAllBody(space.name),
                  );
                  if (!sure) return;
                  await ref.read(askRepositoryProvider).deleteAll();
                  ref.read(askControllerProvider.notifier).startNew();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
