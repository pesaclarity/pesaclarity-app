import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/look/look_settings.dart';
import '../../../routing/app_router.dart';
import '../../../theme/app_theme.dart';
import '../application/look_providers.dart';

/// Draws every text field in the style the person chose. It sits above the
/// router's navigator, so pages, sheets and dialogs all follow it. Nothing
/// is read until the app is unlocked and set up: opening the database while
/// it is locked would fail for the whole session.
class FieldStyleTheme extends ConsumerWidget {
  const FieldStyleTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(launchGateProvider).value ?? false)) return child;
    final style =
        ref.watch(lookSettingsProvider).value?.fields ?? FieldStyle.underlined;
    if (style == FieldStyle.underlined) return child;
    return Theme(
      data: AppTheme.withFields(Theme.of(context), style),
      child: child,
    );
  }
}
