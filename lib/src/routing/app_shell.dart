import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/brand_tokens.dart';
import '../theme/pesa_colors.dart';

/// Five-tab shell with the floating pill navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Activity',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Plan',
    ),
    NavigationDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag),
      label: 'Goals',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Insights',
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
