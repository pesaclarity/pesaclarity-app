import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/ask_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../domain/time/week_start.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart' show formatTime;
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../settings/application/week_start_provider.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/ask_providers.dart';
import 'ask_answer_view.dart';
import 'ask_app_bar.dart';
import 'ask_strings.dart';

/// Saved conversations in the open space, Today, This week and Earlier.
class AskConversationsScreen extends ConsumerStatefulWidget {
  const AskConversationsScreen({super.key});

  @override
  ConsumerState<AskConversationsScreen> createState() =>
      _AskConversationsScreenState();
}

class _AskConversationsScreenState
    extends ConsumerState<AskConversationsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final space = ref.watch(activeSpaceProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final all = ref.watch(askConversationsProvider).value;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in all ?? const <AskConversation>[])
        if (q.isEmpty || c.title.toLowerCase().contains(q)) c,
    ];
    final weekStart = weekStartOn(today, ref.watch(weekStartsOnProvider));
    final groups = <String, List<AskConversation>>{};
    for (final c in shown) {
      final day = CalendarDate.local(c.updatedAt);
      final group = day == today
          ? AskStrings.today
          : (!day.isBefore(weekStart)
                ? AskStrings.thisWeek
                : AskStrings.earlier);
      (groups[group] ??= []).add(c);
    }
    String when(AskConversation c) {
      final day = CalendarDate.local(c.updatedAt);
      if (day == today) return formatTime(c.updatedAt);
      if (!day.isBefore(weekStart)) {
        return const [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ][day.weekday - 1];
      }
      return dayLabel(day, thisYear: today.year);
    }

    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1;
    final titleStyle =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
    final spaceStyle = theme.textTheme.bodySmall!.copyWith(
      color: colors.textMuted,
    );

    return Scaffold(
      appBar: AppBar(
        // At larger text the space's name goes under the title, as in a
        // conversation, so the chip doesn't cut the title short.
        toolbarHeight: largeText
            ? askToolbarHeight(
                context,
                title: AskStrings.conversations,
                titleStyle: titleStyle,
                spaceName: space.name,
                spaceStyle: spaceStyle,
                // Less the back button and the title's spacing either side.
                width: MediaQuery.sizeOf(context).width - kToolbarHeight - 32,
              )
            : null,
        title: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AskStrings.conversations,
                    // The app bar's titles don't wrap unless asked.
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  Text(
                    space.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: spaceStyle,
                  ),
                ],
              )
            : const Text(AskStrings.conversations),
        actions: [
          if (!largeText)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(space.name)),
            ),
        ],
      ),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          // The soft shadow of floating parts, none in dark.
          boxShadow: PesaColors.of(context).floatingShadow,
        ),
        child: FilledButton.icon(
          key: const Key('ask-new-conversation'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: const StadiumBorder(),
            side: BorderSide.none,
          ),
          icon: const Icon(Icons.add),
          label: const Text(AskStrings.newConversation),
          onPressed: () => context.pushReplacement(AppRoutes.ask),
        ),
      ),
      body: all == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Layout.gutter,
                8,
                Layout.gutter,
                Layout.tabBottom,
              ),
              children: [
                TextField(
                  key: const Key('ask-search'),
                  decoration: const InputDecoration(
                    hintText: AskStrings.searchConversations,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyNote(
                      all.isEmpty
                          ? AskStrings.noConversations
                          : AskStrings.noMatches,
                    ),
                  ),
                for (final MapEntry(key: group, value: list)
                    in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text(
                      group,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: colors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, c) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(c.title),
                            subtitle: c.lastReply == null
                                ? null
                                // Wraps, so its amounts stay whole.
                                : Text(_summary(context, c)),
                            trailing: Text(
                              when(c),
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                            onTap: () => context.pushReplacement(
                              AppRoutes.askConversation(c.id),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _summary(BuildContext context, AskConversation c) {
    final answer = c.lastReply!;
    final text = answerText(context, answer);
    return text.isNotEmpty ? text : (answer.headline ?? '');
  }
}
