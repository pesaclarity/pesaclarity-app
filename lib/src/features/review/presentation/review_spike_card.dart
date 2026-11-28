import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/reader/review_spike.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../application/review_spike_providers.dart';

/// "KCB messages changed format", for Home, once per spike: tapping opens
/// messages to check, and either that or Close stops it showing.
class ReviewSpikeCard extends ConsumerWidget {
  const ReviewSpikeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spikes = ref.watch(reviewSpikesProvider);
    if (spikes.isEmpty) return const SizedBox.shrink();
    final spike = spikes.first;
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final name =
        ref
            .watch(institutionCatalogueProvider)
            .where((i) => i.id == spike.institutionId)
            .firstOrNull
            ?.name ??
        spike.institutionId;
    void told() => ref.read(reviewSpikeToldProvider.notifier).told(spike);
    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Card(
        key: Key('review-spike-${spike.institutionId}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            told();
            context.push(AppRoutes.review);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Layout.cardPadding + 4,
              Layout.cardPadding,
              4,
              Layout.cardPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name messages changed format',
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          spikeBody(spike),
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
                  onPressed: told,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 20, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "14 need checking. Check one and the rest follow."
String spikeBody(ReviewSpike spike) =>
    '${spike.waiting} ${spike.waiting == 1 ? 'needs' : 'need'} checking. '
    'Check one and the rest follow.';
