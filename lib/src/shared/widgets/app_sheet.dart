import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import '../accessibility.dart';

/// Opens a sheet from the bottom the same way everywhere: as tall as it
/// needs, with a handle to drag it away and a close button, clear of the
/// phone's edges. Build it with [SheetBody].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Shows in place, without sliding up, when the phone asks for less
  // motion.
  sheetAnimationStyle: reduceMotion(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => SheetFrame(child: builder(context)),
);

/// The top of every sheet: the drag handle in the middle and a close
/// button at the start, so a sheet can be shut with a tap as well as a
/// drag. [child] goes under it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({required this.child, super.key});

  final Widget child;

  /// The height of the row with the handle and the close button.
  static const topHeight = Layout.minTouch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: topHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 4,
                top: 0,
                bottom: 0,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}

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
              Semantics(
                header: true,
                child: Text(title!, style: theme.textTheme.headlineSmall),
              ),
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
