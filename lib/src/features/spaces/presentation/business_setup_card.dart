import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/business_setup_providers.dart';

/// On a business's Home until it has said what it sells and started its
/// records.
class BusinessSetupCard extends ConsumerWidget {
  const BusinessSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(businessSetupProvider).value;
    if (setup == null || setup.isDone) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-business-setup'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: const Text('Set up your business records'),
          subtitle: Text(
            setup.sells == null
                ? 'What you sell, and what the business has today'
                : 'What the business has today',
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => context.push(
            setup.sells == null
                ? AppRoutes.whatYouSell
                : AppRoutes.startRecords,
          ),
        ),
      ),
    );
  }
}
