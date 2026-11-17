import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/app_status_providers.dart';
import '../application/update_links.dart';
import '../domain/app_status.dart';

/// Home's cards under the lead card: "Pesa Clarity 0.4.0 is ready" with an
/// Update button, and news from the team, such as a bank changing its
/// messages. Each can be closed; an update comes back when a newer one is
/// out. Nothing shows until a response has been verified.
class AppNoticeCards extends ConsumerWidget {
  const AppNoticeCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(appStatusProvider).value;
    if (view == null || view.blocking != null) return const SizedBox.shrink();
    final cards = view.cards;
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in cards)
          AppNoticeCard(
            notice,
            onUpdate: notice.kind == AppNoticeKind.update
                ? () => openUpdate(ref)
                : null,
            onClose: () => ref.read(appStatusProvider.notifier).dismiss(notice),
          ),
      ],
    );
  }
}

/// One notice: its title and text, a close button, and Update for an
/// update.
class AppNoticeCard extends StatelessWidget {
  const AppNoticeCard(
    this.notice, {
    required this.onClose,
    this.onUpdate,
    super.key,
  });

  final AppNotice notice;
  final VoidCallback onClose;

  /// Null hides the Update button, as for news.
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Card(
        key: Key('app-notice-${notice.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.cardPadding + 4,
            Layout.cardPadding,
            4,
            Layout.cardPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notice.title,
                            style: theme.textTheme.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            notice.body,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: colors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, size: 20, color: colors.textMuted),
                  ),
                ],
              ),
              if (onUpdate != null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(
                    // Neutral, so red stays for the lead card.
                    backgroundColor: colors.selected,
                    foregroundColor: theme.colorScheme.onSurface,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: const Text('Update'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
