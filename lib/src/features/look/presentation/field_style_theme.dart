import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/look/look_settings.dart';
import '../../../theme/app_theme.dart';
import '../application/look_providers.dart';

/// Draws every text field in the style the person chose. It sits above app
/// lock and the router's navigator, so the lock screen, setup, pages, sheets
/// and dialogs all follow it.
class FieldStyleTheme extends ConsumerWidget {
  const FieldStyleTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(currentLookProvider).fields;
    if (style == FieldStyle.underlined) return child;
    return Theme(
      data: AppTheme.withFields(Theme.of(context), style),
      child: child,
    );
  }
}
