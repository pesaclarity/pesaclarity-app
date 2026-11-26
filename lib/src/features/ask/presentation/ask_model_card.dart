import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/adaptive/adaptive.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../model/ask_model_catalogue.dart';
import '../model/ask_model_controller.dart';
import 'ask_strings.dart';

int _mb(int bytes) => (bytes / 1000000).round();

/// In a conversation: "Get better answers" once, on phones that can run a
/// model, then the download's progress. Nothing otherwise.
class AskModelCard extends ConsumerWidget {
  const AskModelCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(askModelControllerProvider);
    if (!state.offerVisible && !state.downloadVisible) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(askModelControllerProvider.notifier);
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final body = theme.textTheme.bodyMedium!;
    final title = theme.textTheme.titleMedium!;
    final List<Widget> children;
    if (state.downloadVisible) {
      final target = state.target!;
      final progress = state.progress;
      final line = switch (state.phase) {
        AskModelPhase.waitingForWifi => AskStrings.waitingForWifi,
        AskModelPhase.checking => AskStrings.checkingModel,
        AskModelPhase.failed => switch (state.problem) {
          AskModelProblem.space => AskStrings.failedSpace,
          AskModelProblem.mismatch => AskStrings.failedMismatch,
          AskModelProblem.tooSlow => AskStrings.failedTooSlow,
          _ => AskStrings.failedNetwork,
        },
        _ => AskStrings.progress(
          _mb(progress.received),
          target.sizeMb,
          state.onWifi ? AskStrings.wifi : AskStrings.mobile,
          state.secondsLeft,
        ),
      };
      final failed = state.phase == AskModelPhase.failed;
      children = [
        Text(AskStrings.gettingBetterAnswers, style: title),
        const SizedBox(height: 4),
        Text(AskStrings.tierName(target.tier.name), style: muted),
        if (!failed) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const Key('ask-model-progress'),
              value: state.phase == AskModelPhase.downloading
                  ? progress.fraction
                  : null,
              minHeight: 6,
              color: theme.colorScheme.onSurface,
              backgroundColor: colors.textMuted.withValues(alpha: .2),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(line, key: const Key('ask-model-status'), style: body),
        const SizedBox(height: 8),
        Text(AskStrings.keepsWorking, style: muted),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed && state.problem != AskModelProblem.tooSlow)
                TextButton(
                  key: const Key('ask-model-retry'),
                  onPressed: () => controller.download(target.tier),
                  child: const Text(AskStrings.tryAgain),
                ),
              TextButton(
                key: const Key('ask-model-cancel'),
                onPressed: controller.cancel,
                child: Text(failed ? AskStrings.notNow : AskStrings.cancel),
              ),
            ],
          ),
        ),
      ];
    } else {
      final first = state.capable.first;
      children = [
        Text(AskStrings.getBetterAnswers, style: title),
        const SizedBox(height: 6),
        Text(AskStrings.offerBody, style: body),
        const SizedBox(height: 10),
        Text(
          [
            for (final m in state.capable)
              AskStrings.offerLine(
                m.tier.name,
                m.parameters,
                m.sizeMb,
                m.minRamMb,
              ),
          ].join('\n'),
          style: body,
        ),
        const SizedBox(height: 8),
        Text(AskStrings.offerFootnote, style: muted),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              key: const Key('ask-model-download'),
              onPressed: () => controller.download(first.tier),
              child: Text(AskStrings.download(first.tier.name, first.sizeMb)),
            ),
            TextButton(
              key: const Key('ask-model-not-now'),
              onPressed: controller.notNow,
              child: const Text(AskStrings.notNow),
            ),
          ],
        ),
      ];
    }
    return Card(
      key: const Key('ask-model-card'),
      margin: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// Ask settings › Answers: Light, Full, No model, mobile data, delete, and
/// the model's licence. Only on phones that can run a model.
class AskAnswersSection extends ConsumerWidget {
  const AskAnswersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(askModelControllerProvider);
    if (!state.settingsVisible) return const SizedBox.shrink();
    final controller = ref.read(askModelControllerProvider.notifier);
    final theme = Theme.of(context);
    final red = theme.colorScheme.primary;
    final busy =
        state.phase == AskModelPhase.downloading ||
        state.phase == AskModelPhase.checking;
    final models = [
      for (final m in state.catalogue.models)
        if (state.capable.contains(m) || m.tier == state.installed) m,
    ];
    final installed = state.installed == null
        ? null
        : state.catalogue[state.installed!];
    final credit = installed ?? (models.isEmpty ? null : models.first);
    Widget choice({
      required Key key,
      required String title,
      required String subtitle,
      required bool on,
      required VoidCallback onTap,
    }) => ListTile(
      key: key,
      title: Text(title, style: on ? TextStyle(color: red) : null),
      subtitle: Text(subtitle),
      trailing: on ? Icon(Icons.check, color: red) : null,
      onTap: onTap,
    );
    String detail(AskModelEntry m) {
      if (state.target == m && state.phase != AskModelPhase.idle) {
        return switch (state.phase) {
          AskModelPhase.waitingForWifi => AskStrings.waitingForWifi,
          AskModelPhase.checking => AskStrings.checkingModel,
          AskModelPhase.failed => AskStrings.failedNetwork,
          _ => AskStrings.progress(
            _mb(state.progress.received),
            m.sizeMb,
            state.onWifi ? AskStrings.wifi : AskStrings.mobile,
            state.secondsLeft,
          ),
        };
      }
      return AskStrings.tierDetail(
        m.tier.name,
        m.parameters,
        m.sizeMb,
        m.minRamMb,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Layout.cardGap),
      child: GroupedSection(
        header: AskStrings.answers,
        footer: credit == null
            ? null
            : AskStrings.modelCredit(credit.credit, credit.licence),
        children: [
          for (final m in models)
            choice(
              key: Key('ask-model-${m.tier.name}'),
              title: AskStrings.tierName(m.tier.name),
              subtitle: detail(m),
              on: state.selected == m.tier && state.installed == m.tier,
              onTap: busy ? () {} : () => controller.choose(m.tier),
            ),
          choice(
            key: const Key('ask-model-none'),
            title: AskStrings.noModel,
            subtitle: AskStrings.noModelDetail,
            on: state.active == null,
            onTap: () {
              controller.cancel();
              controller.choose(null);
            },
          ),
          SwitchListTile.adaptive(
            key: const Key('ask-model-mobile-data'),
            title: const Text(AskStrings.mobileData),
            subtitle: const Text(AskStrings.mobileDataDetail),
            value: state.mobileData,
            onChanged: controller.setMobileData,
          ),
          if (installed != null)
            ListTile(
              key: const Key('ask-model-delete'),
              title: const Text(AskStrings.deleteModel),
              subtitle: Text(AskStrings.frees(installed.sizeMb)),
              onTap: () async {
                final sure = await confirmDelete(
                  context,
                  title: AskStrings.deleteModelQuestion,
                  body: AskStrings.deleteModelBody,
                );
                if (sure) await controller.deleteModel();
              },
            ),
        ],
      ),
    );
  }
}
