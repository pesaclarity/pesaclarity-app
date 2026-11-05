import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/spaces/space.dart';
import '../features/currency/application/currency_controller.dart';
import '../features/privacy/application/consent_controller.dart';
import '../features/privacy/presentation/policy_review_screen.dart';
import '../features/reminders/application/reminders_controller.dart';
import '../features/sms/application/sms_capture_providers.dart';
import '../features/spaces/application/spaces_providers.dart';
import '../shared/semantic_ids.dart';
import '../theme/pesa_colors.dart';

/// The shell's branches, in the order the router lists them.
enum ShellBranch { home, activity, plan, goals, insights, money }

/// Personal's tabs, and those of every space without its own.
const personalTabs = [
  PillDestination(
    id: SemanticIds.navHome,
    branch: ShellBranch.home,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  PillDestination(
    id: SemanticIds.navActivity,
    branch: ShellBranch.activity,
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Activity',
  ),
  PillDestination(
    id: SemanticIds.navPlan,
    branch: ShellBranch.plan,
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    label: 'Plan',
  ),
  PillDestination(
    id: SemanticIds.navGoals,
    branch: ShellBranch.goals,
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag,
    label: 'Goals',
  ),
  PillDestination(
    id: SemanticIds.navInsights,
    branch: ShellBranch.insights,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    label: 'Insights',
  ),
];

/// A business's tabs. People and Stock join as they are built.
const businessTabs = [
  PillDestination(
    id: SemanticIds.navHome,
    branch: ShellBranch.home,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Today',
  ),
  PillDestination(
    id: SemanticIds.navMoney,
    branch: ShellBranch.money,
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments,
    label: 'Money',
  ),
  PillDestination(
    id: SemanticIds.navInsights,
    branch: ShellBranch.insights,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    label: 'Insights',
  ),
];

/// The tabs for a space of [kind].
List<PillDestination> tabsFor(SpaceKind kind) =>
    kind == SpaceKind.business ? businessTabs : personalTabs;

/// Which of [tabs] to show as current while [branch] is open: its own tab,
/// or the tab it opens from (a business's full Activity list opens from
/// Money). -1 when none fits.
int selectedTabOf(List<PillDestination> tabs, ShellBranch branch) {
  final own = tabs.indexWhere((t) => t.branch == branch);
  if (own >= 0) return own;
  final parent = switch (branch) {
    ShellBranch.activity => ShellBranch.money,
    _ => null,
  };
  return tabs.indexWhere((t) => t.branch == parent);
}

/// The tabbed shell with the floating pill navigation bar, on Android and
/// iPhone alike. A business gets its own tabs in the same bar. While it is
/// shown, new account messages flow into the ledger, reminders stay
/// scheduled, and a newer privacy policy is put up for review.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveSmsCaptureProvider, (_, _) {});
    ref.listen(reminderSyncProvider, (_, _) {});
    ref.listen(ratesRefreshProvider, (_, _) {});
    ref.listen(policyReviewProvider, (_, next) {
      // While reloading, value still holds the previous changes.
      if (next case AsyncData(value: final changes?)) {
        showPolicyReview(context, changes);
      }
    });
    final tabs = tabsFor(ref.watch(activeSpaceProvider).kind);
    final current = navigationShell.currentIndex;
    void select(int index) {
      final branch = tabs[index].branch.index;
      navigationShell.goBranch(branch, initialLocation: branch == current);
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: PillNavigationBar(
          destinations: tabs,
          selectedIndex: selectedTabOf(tabs, ShellBranch.values[current]),
          onSelected: select,
        ),
      ),
    );
  }
}

/// One tab in [PillNavigationBar].
class PillDestination {
  const PillDestination({
    required this.id,
    required this.branch,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// The semantics identifier UI flows tap, such as `nav-home`.
  final String id;

  /// The branch the tab opens.
  final ShellBranch branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The floating pill from the design: icons over labels, the current tab in
/// the brand colour and bold, with no indicator behind it. A
/// [selectedIndex] of -1 shows no tab as current.
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
