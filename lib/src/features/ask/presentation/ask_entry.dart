import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/ask_settings.dart';
import 'ask_strings.dart';

// Ask's ways in: the Ask bar above the tabs, the Ask button in Home's top
// bar, and "Ask about" links. Each checks Show Ask itself, so a screen only
// places them.

/// Whether Ask's ways in show in the open space (Show Ask).
final askShownProvider = Provider<bool>(
  (ref) => ref.watch(askSettingsProvider).value?.show ?? true,
);

/// Whether the Ask bar has slid away on a scrolled screen, so the top-bar
/// button takes its place. One Ask control shows at a time.
class AskBarAway extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool away) {
    if (state != away) state = away;
  }
}

final askBarAwayProvider = NotifierProvider<AskBarAway, bool>(AskBarAway.new);

/// The Ask button in Home's top bar, beside Profile. Tinted while the Ask
/// bar is away.
class AskHomeButton extends ConsumerWidget {
  const AskHomeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(askShownProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final away = ref.watch(askBarAwayProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton.outlined(
        key: const Key('home-ask'),
        tooltip: AskStrings.title,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        style: IconButton.styleFrom(
          backgroundColor: away ? colors.brandSoft : theme.colorScheme.surface,
          foregroundColor: away
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          side: BorderSide(
            color: away ? theme.colorScheme.primary : colors.border,
          ),
        ),
        icon: const Icon(Icons.chat_bubble_outline),
        onPressed: () => context.push(AppRoutes.ask),
      ),
    );
  }
}

/// The Ask bar: a box-like button that opens Ask, with an Ask pill.
class AskBar extends StatelessWidget {
  const AskBar({required this.label, required this.route, super.key});

  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        key: const Key('ask-bar'),
        color: theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.25),
              colors.brandSoft,
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(route),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.chat_bubble_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: colors.brandSoft,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    AskStrings.send,
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child], a scrolling screen, with the Ask bar over its foot. The bar
/// slides away as the person scrolls down and comes back at the top.
/// Without [label], it asks about the open space.
class AskBarScope extends ConsumerStatefulWidget {
  const AskBarScope({
    required this.child,
    this.label,
    this.route = AppRoutes.ask,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final String? label;
  final String route;

  /// Off, the bar does not show, as on Activity without filters.
  final bool enabled;

  @override
  ConsumerState<AskBarScope> createState() => _AskBarScopeState();
}

class _AskBarScopeState extends ConsumerState<AskBarScope> {
  bool _away = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final away = n.metrics.pixels > 24;
    if (away != _away) {
      setState(() => _away = away);
      ref.read(askBarAwayProvider.notifier).set(away);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.enabled && ref.watch(askShownProvider);
    final space = ref.watch(activeSpaceProvider);
    final label =
        widget.label ??
        (space.kind == SpaceKind.personal
            ? AskStrings.hint
            : AskStrings.hintFor(space.name));
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        if (shown)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: _away,
              child: AnimatedSlide(
                offset: _away ? const Offset(0, 1) : Offset.zero,
                duration: const Duration(milliseconds: 200),
                child: AnimatedOpacity(
                  opacity: _away ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    // A soft fade so the list does not clash with the bar.
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [background.withValues(alpha: 0), background],
                        stops: const [0, 0.4],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: AskBar(label: label, route: widget.route),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A link that opens Ask about a category and month, such as "Ask about
/// food this month".
class AskAboutLink extends ConsumerWidget {
  const AskAboutLink(this.label, {this.categoryId, this.month, super.key});

  final String label;
  final int? categoryId;
  final YearMonth? month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(askShownProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final m = month;
    return InkWell(
      key: const Key('ask-about'),
      onTap: () => context.push(
        AppRoutes.askAbout(
          categoryId: categoryId,
          month: m == null
              ? null
              : '${m.year}-${m.month.toString().padLeft(2, '0')}',
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
