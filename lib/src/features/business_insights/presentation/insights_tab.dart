import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/spaces/space.dart';
import '../../insights/presentation/insights_screen.dart';
import '../../spaces/application/spaces_providers.dart';
import 'business_insights_screen.dart';

/// The Insights tab: how the business is doing in a business, else the
/// personal insights.
class InsightsTab extends ConsumerWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(activeSpaceProvider).kind == SpaceKind.business
      ? const BusinessInsightsScreen()
      : const InsightsScreen();
}
