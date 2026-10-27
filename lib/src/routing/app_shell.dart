import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/privacy/application/consent_controller.dart';
import '../features/privacy/presentation/policy_review_screen.dart';
import '../features/reminders/application/reminders_controller.dart';
import '../features/sms/application/notification_capture.dart';
import '../features/sms/application/sms_capture_providers.dart';
import '../shared/semantic_ids.dart';
import '../theme/brand_tokens.dart';
import '../theme/pesa_colors.dart';

/// Five-tab shell with the floating pill navigation bar. While it is shown,
/// new account messages flow into the ledger, reminders stay scheduled, and
/// a newer privacy policy is put up for review.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static final _destinations = <Widget>[
    Semantics(
      identifier: SemanticIds.navHome,
      child: const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
    ),
    Semantics(
      identifier: SemanticIds.navActivity,
      child: const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Activity',
      ),
    ),
    Semantics(
      identifier: SemanticIds.navPlan,
      child: const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Plan',
      ),
    ),
    Semantics(
      identifier: SemanticIds.navGoals,
      child: const NavigationDestination(
        icon: Icon(Icons.flag_outlined),
        selectedIcon: Icon(Icons.flag),
        label: 'Goals',
      ),
    ),
    Semantics(
      identifier: SemanticIds.navInsights,
      child: const NavigationDestination(
        icon: Icon(Icons.insights_outlined),
        selectedIcon: Icon(Icons.insights),
        label: 'Insights',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveSmsCaptureProvider, (_, _) {});
    ref.listen(liveNotificationCaptureProvider, (_, _) {});
    ref.listen(reminderSyncProvider, (_, _) {});
    ref.listen(policyReviewProvider, (_, next) {
      // While reloading, value still holds the previous changes.
      if (next case AsyncData(value: final changes?)) {
        showPolicyReview(context, changes);
      }
    });
    final scheme = Theme.of(context).colorScheme;
    final colors = PesaColors.of(context);
    final pill = BorderRadius.circular(BrandTokens.pillRadius);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: pill,
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: scheme.onSurface.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: pill,
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              destinations: _destinations,
              onDestinationSelected: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
