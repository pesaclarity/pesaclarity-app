import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/spaces/business_setup.dart';
import '../domain/spaces/space.dart';
import '../features/balances/application/balances_providers.dart';
import '../features/currency/application/currency_controller.dart';
import '../features/home/presentation/add_menu.dart';
import '../features/invoices/application/invoice_providers.dart';
import '../features/privacy/application/consent_controller.dart';
import '../features/privacy/presentation/policy_review_screen.dart';
import '../features/reminders/application/reminders_controller.dart';
import '../features/sales/application/pay_yourself.dart';
import '../features/sales/application/sales_providers.dart';
import '../features/sms/application/sms_capture_providers.dart';
import '../features/spaces/application/business_setup_providers.dart';
import '../features/spaces/application/spaces_providers.dart';
import '../shared/accessibility.dart';
import '../shared/semantic_ids.dart';
import '../theme/pesa_colors.dart';

/// The shell's branches, in the order the router lists them.
enum ShellBranch { home, activity, plan, goals, insights, money, people, stock }

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

/// A business's tabs.
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
    id: SemanticIds.navPeople,
    branch: ShellBranch.people,
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: 'People',
  ),
  PillDestination(
    id: SemanticIds.navStock,
    branch: ShellBranch.stock,
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    label: 'Stock',
  ),
  PillDestination(
    id: SemanticIds.navInsights,
    branch: ShellBranch.insights,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    label: 'Insights',
  ),
];

/// A services business's tabs: its customers are clients, and what it
/// sells is services.
final serviceTabs = [
  for (final t in businessTabs)
    switch (t.branch) {
      ShellBranch.people => PillDestination(
        id: t.id,
        branch: t.branch,
        icon: t.icon,
        selectedIcon: t.selectedIcon,
        label: 'Clients',
      ),
      ShellBranch.stock => PillDestination(
        id: t.id,
        branch: t.branch,
        icon: Icons.work_outline,
        selectedIcon: Icons.work,
        label: 'Services',
      ),
      _ => t,
    },
];

/// The tabs for a space of [kind]; a business that sells only [services]
/// has clients.
List<PillDestination> tabsFor(SpaceKind kind, {bool services = false}) =>
    kind != SpaceKind.business
    ? personalTabs
    : services
    ? serviceTabs
    : businessTabs;

/// Which of [tabs] to show as current while [branch] is open: its own tab,
/// or the tab it opens from (a business's full Activity list opens from
/// Money, and Lent and borrowed from People). -1 when none fits.
int selectedTabOf(List<PillDestination> tabs, ShellBranch branch) {
  final own = tabs.indexWhere((t) => t.branch == branch);
  if (own >= 0) return own;
  final parent = switch (branch) {
    ShellBranch.activity => ShellBranch.money,
    ShellBranch.goals => ShellBranch.people,
    _ => null,
  };
  return tabs.indexWhere((t) => t.branch == parent);
}

/// The tabbed shell with the floating pill navigation bar, on Android and
/// iPhone alike. A business gets its own tabs in the same bar. While it is
/// shown, new account messages flow into the ledger, reminders stay
/// scheduled, a business's sales meet their payment messages, and a newer
/// privacy policy is put up for review.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveSmsCaptureProvider, (_, _) {});
    ref.listen(pairHistoryOnceProvider, (_, _) {});
    ref.listen(reminderSyncProvider, (_, _) {});
    ref.listen(ratesRefreshProvider, (_, _) {});
    ref.listen(saleMatcherProvider, (_, _) {});
    ref.listen(invoiceMatcherProvider, (_, _) {});
    ref.listen(personalPayMatcherProvider, (_, _) {});
    ref.listen(policyReviewProvider, (_, next) {
      // While reloading, value still holds the previous changes.
      if (next case AsyncData(value: final changes?)) {
        showPolicyReview(context, changes);
      }
    });
    final kind = ref.watch(activeSpaceProvider).kind;
    final tabs = tabsFor(
      kind,
      services:
          kind == SpaceKind.business &&
          ref.watch(businessSetupProvider).value?.sells ==
              BusinessSells.services,
    );
    final current = navigationShell.currentIndex;
    void select(int index) {
      final branch = tabs[index].branch.index;
      navigationShell.goBranch(branch, initialLocation: branch == current);
    }

    final iPhone = defaultTargetPlatform == TargetPlatform.iOS;
    final selected = selectedTabOf(tabs, ShellBranch.values[current]);
    final body = Stack(
      children: [
        navigationShell,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TabBarFade(
            // On iPhone the content runs on under the glass bar, so the
            // fade reaches the foot of the screen.
            extra: iPhone
                ? PillNavigationBar.height +
                      math.max(
                        MediaQuery.paddingOf(context).bottom,
                        PillNavigationBar.iPhoneInset,
                      )
                : 0,
          ),
        ),
      ],
    );
    return Scaffold(
      // On iPhone the bar is glass with the content passing under it.
      extendBody: iPhone,
      body: iPhone
          ? CollapsingTabTitle(
              title: selected < 0 ? null : tabs[selected].label,
              resetKey: '$current ${GoRouterState.of(context).uri}',
              child: body,
            )
          : body,
      // The one main action sits beside the bar, never over the list.
      bottomNavigationBar: SafeArea(
        minimum: iPhone
            ? const EdgeInsets.fromLTRB(
                PillNavigationBar.iPhoneInset,
                0,
                PillNavigationBar.iPhoneInset,
                PillNavigationBar.iPhoneInset,
              )
            : const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: Row(
          children: [
            Expanded(
              child: PillNavigationBar(
                destinations: tabs,
                selectedIndex: selected,
                glass: iPhone,
                onSelected: select,
              ),
            ),
            const SizedBox(width: 12),
            const MainAddButton(),
          ],
        ),
      ),
    );
  }
}

/// On iPhone, a tab's [title] small and centred in a bar at the top once
/// the tab's large title has scrolled away, as iOS does. Only the tab's own
/// screen counts: a pushed screen has its own bar. A new [resetKey] (another
/// tab or screen) hides it until the next scroll.
class CollapsingTabTitle extends StatefulWidget {
  const CollapsingTabTitle({
    required this.title,
    required this.resetKey,
    required this.child,
    super.key,
  });

  final String? title;
  final String resetKey;
  final Widget child;

  /// How far a tab scrolls before its title moves into the bar: about the
  /// large title's height.
  static const threshold = 44.0;

  /// The bar's height under the status bar.
  static const barHeight = 44.0;

  @override
  State<CollapsingTabTitle> createState() => _CollapsingTabTitleState();
}

class _CollapsingTabTitleState extends State<CollapsingTabTitle> {
  bool _shown = false;

  @override
  void didUpdateWidget(CollapsingTabTitle old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) _shown = false;
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final context = n.context;
    // A tab's own screen has no app bar; a pushed screen does.
    final ownScreen =
        context != null && Scaffold.maybeOf(context)?.widget.appBar == null;
    final shown = ownScreen && n.metrics.pixels > CollapsingTabTitle.threshold;
    if (shown != _shown) setState(() => _shown = shown);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;
    final top = MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (title != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !_shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  // The large title is the heading people hear.
                  child: ExcludeSemantics(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          key: const Key('collapsed-tab-title'),
                          height: top + CollapsingTabTitle.barHeight,
                          padding: EdgeInsets.only(top: top),
                          alignment: Alignment.center,
                          color: theme.scaffoldBackgroundColor.withValues(
                            alpha: 0.85,
                          ),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades a tab's content out as it reaches the tab bar, rather than cutting
/// it off at the bar's top edge. It takes no taps.
class TabBarFade extends StatelessWidget {
  const TabBarFade({this.extra = 0, super.key});

  static const height = 24.0;

  /// More height under the fade, where content passes under the bar.
  final double extra;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          height: height + extra,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [background.withValues(alpha: 0), background],
              ),
            ),
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
/// the text colour and bold, with no indicator behind it. A
/// [selectedIndex] of -1 shows no tab as current.
class PillNavigationBar extends StatelessWidget {
  const PillNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.glass = false,
    super.key,
  });

  static const height = 68.0;

  /// The space iOS leaves each side of and under its tab bar.
  static const iPhoneInset = 21.0;

  /// On iPhone: translucent and blurred, with the content showing faintly
  /// through it, like iOS's own tab bar.
  final bool glass;

  final List<PillDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The text size for every tab's label: the phone's, or smaller when the
  /// widest label, in bold as when chosen, would not fit [width] at it.
  /// Never smaller than the usual size if that fits.
  TextScaler labelScaler(BuildContext context, double width) {
    final style = _PillItem.labelStyle(context, selected: true);
    double widest(TextScaler scaler) {
      var widest = 0.0;
      for (final d in destinations) {
        final painter = TextPainter(
          text: TextSpan(text: d.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
      return widest;
    }

    final base = MediaQuery.textScalerOf(context);
    final size = style.fontSize ?? 11;
    var scaler = base;
    // Width is not quite in proportion to size (letter spacing does not
    // grow), so narrow it down in a few steps.
    for (var i = 0; i < 4; i++) {
      final w = widest(scaler);
      if (w <= width || w == 0) return scaler;
      scaler = TextScaler.linear(scaler.scale(size) / size * width / w * 0.99);
    }
    return scaler;
  }

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    const shape = StadiumBorder();

    final bar = Container(
      height: height,
      decoration: ShapeDecoration(
        color: glass
            ? colors.floating.withValues(alpha: 0.72)
            : colors.floating,
        shape: StadiumBorder(side: BorderSide(color: colors.border)),
        shadows: colors.floatingShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // Every label at one size: the phone's text size, or, when the
        // longest name would not fit its tab at that size, the size at
        // which it does, so no label ends in "..." and none looks smaller
        // than the others.
        child: LayoutBuilder(
          builder: (context, constraints) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: labelScaler(
                context,
                constraints.maxWidth / destinations.length -
                    2 * _PillItem.labelPadding,
              ),
            ),
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
        ),
      ),
    );
    if (!glass) return bar;
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: StadiumBorder()),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: bar,
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

  /// Space each side of a label, clear of the bar's rounded ends.
  static const labelPadding = 5.0;

  static TextStyle labelStyle(BuildContext context, {required bool selected}) {
    final color = selected
        ? PesaColors.of(context).link
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Theme.of(context).textTheme.labelSmall!.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected
        ? PesaColors.of(context).link
        : scheme.onSurfaceVariant;

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
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _PillItem.labelPadding,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                softWrap: false,
                style: labelStyle(context, selected: selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
