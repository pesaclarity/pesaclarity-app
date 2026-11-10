import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// Opens a sheet from the bottom the same way everywhere: as tall as it
/// needs, with a handle to drag it away, clear of the phone's edges. Build
/// it with [SheetBody].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: builder,
);

/// A sheet's content: its [title], an optional [subtitle], then
/// [children] at full width. The main button goes last in [children]. It
/// scrolls when tall and stays above the keyboard.
class SheetBody extends StatelessWidget {
  const SheetBody({
    required this.children,
    this.title,
    this.subtitle,
    super.key,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        // Clear of the phone's gesture bar, which the sheet's safe area
        // leaves out.
        padding: EdgeInsets.fromLTRB(
          Layout.gutter,
          0,
          Layout.gutter,
          Layout.screenBottom + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(title!, style: theme.textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: PesaColors.of(context).textMuted,
                ),
              ),
            ],
            if (title != null || subtitle != null) const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
