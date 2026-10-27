import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/privacy/application/consent_controller.dart';
import '../features/privacy/presentation/policy_review_screen.dart';
import '../features/reminders/application/reminders_controller.dart';
import '../features/sms/application/sms_capture_providers.dart';
import '../shared/semantic_ids.dart';
import '../theme/pesa_colors.dart';

/// Five-tab shell with the floating pill navigation bar. While it is shown,
/// new account messages flow into the ledger, reminders stay scheduled, and
/// a newer privacy policy is put up for review.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    PillDestination(
      id: SemanticIds.navHome,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    PillDestination(
      id: SemanticIds.navActivity,
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Activity',
    ),
    PillDestination(
      id: SemanticIds.navPlan,
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Plan',
    ),
    PillDestination(
      id: SemanticIds.navGoals,
      icon: Icons.flag_outlined,
      selectedIcon: Icons.flag,
      label: 'Goals',
    ),
    PillDestination(
      id: SemanticIds.navInsights,
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: 'Insights',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveSmsCaptureProvider, (_, _) {});
    ref.listen(reminderSyncProvider, (_, _) {});
    ref.listen(policyReviewProvider, (_, next) {
      // While reloading, value still holds the previous changes.
      if (next case AsyncData(value: final changes?)) {
        showPolicyReview(context, changes);
      }
    });
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: PillNavigationBar(
          destinations: _destinations,
          selectedIndex: navigationShell.currentIndex,
          onSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}

/// One tab in [PillNavigationBar].
class PillDestination {
  const PillDestination({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// The semantics identifier UI flows tap, such as `nav-home`.
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The floating pill from the design: icons over labels, the current tab in
/// the brand colour and bold, with no indicator behind it.
class PillNavigationBar extends StatelessWidget {
  const PillNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  static const height = 68.0;

  final List<PillDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = PesaColors.of(context);
    const shape = StadiumBorder();

    return Container(
      height: height,
      decoration: ShapeDecoration(
        color: scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: colors.border)),
        shadows: [
          BoxShadow(
            color: scheme.onSurface.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (final (index, destination) in destinations.indexed)
              Expanded(
                child: _PillItem(
                  destination: destination,
                  selected: index == selectedIndex,
                  position: '${index + 1} of ${destinations.length}',
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.destination,
    required this.selected,
    required this.position,
    required this.onTap,
  });

  final PillDestination destination;
  final bool selected;
  final String position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      identifier: destination.id,
      container: true,
      button: true,
      selected: selected,
      label: '${destination.label}, tab $position',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
