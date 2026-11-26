import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/about_you/about_you.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/about_you_providers.dart';
import 'setup_parts.dart';

/// About you: three short questions, each skippable. Offered after the
/// first look at the money at setup, once more on Home, and in Profile.
/// Plan starts with the payments picked and Goals suggests one goal; the
/// answers stay on this phone.
class AboutYouScreen extends ConsumerStatefulWidget {
  const AboutYouScreen({this.onboarding = false, super.key});

  /// At setup, finishing or skipping all ends setup and opens Home; from
  /// Profile or Home it goes back.
  final bool onboarding;

  @override
  ConsumerState<AboutYouScreen> createState() => _AboutYouScreenState();
}

class _AboutYouScreenState extends ConsumerState<AboutYouScreen> {
  var _step = 0;
  var _why = false;
  var _saving = false;
  var _failed = false;
  WhoYouAre? _who;
  var _whoTouched = false;
  Set<WhatMatters>? _matters;
  Set<RegularPayment>? _pays;

  static const _whys = [
    'It picks which goal we suggest. Nothing else changes.',
    'It picks your first goal. Nothing else changes.',
    'Plan starts with these categories, with amounts from your messages '
        'when we find them.',
  ];

  AboutYou? get _saved => ref.read(aboutYouProvider).value;

  WhoYouAre? get _whoNow => _whoTouched ? _who : _saved?.who;
  Set<WhatMatters> get _mattersNow => _matters ?? _saved?.matters ?? const {};
  Set<RegularPayment> get _paysNow => _pays ?? _saved?.pays ?? const {};

  void _next() {
    if (_step < 2) {
      setState(() {
        _step++;
        _why = false;
      });
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _step--;
        _why = false;
      });
    } else {
      _leave();
    }
  }

  /// Saves the answers, starts Plan with what is paid regularly, and
  /// leaves.
  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    var planned = 0;
    try {
      final AboutYou base = await ref.read(aboutYouProvider.future);
      final answers = base.copyWith(
        who: () => _whoNow,
        matters: _mattersNow,
        pays: _paysNow,
        answered: true,
      );
      await ref.read(aboutYouProvider.notifier).save(answers);
      planned = await startPlanFrom(ref, answers);
    } on Object catch (error) {
      debugPrint('About you could not be saved: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    if (!widget.onboarding && planned > 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              planned == 1
                  ? 'Plan starts with 1 category from your answers.'
                  : 'Plan starts with $planned categories from your answers.',
            ),
          ),
        );
    }
    await _leave();
  }

  Future<void> _leave() async {
    if (widget.onboarding) {
      await finishSetup(context, ref);
    } else if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    // Answers saved earlier show once read.
    ref.watch(aboutYouProvider);
    final (title, intro) = switch (_step) {
      0 => ('Which best describes you now?', 'Choose one.'),
      1 => ('What matters most?', 'Pick one or more.'),
      _ => (
        'Which do you pay regularly?',
        'Pick all that fit. Each becomes a category in Plan.',
      ),
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('About you'),
          actions: [
            TextButton(
              key: const Key('about-skip-all'),
              onPressed: _saving ? null : _leave,
              child: const Text('Skip all'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Layout.gutter,
              8,
              Layout.gutter,
              Layout.screenBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_step + 1} of 3',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: 8),
                Text(
                  intro,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('about-why'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onPressed: () => setState(() => _why = !_why),
                    icon: Icon(_why ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Why we ask'),
                  ),
                ),
                if (_why)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 28,
                      bottom: 8,
                    ),
                    child: Text(_whys[_step], style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 4),
                switch (_step) {
                  0 => _Picks(
                    single: true,
                    items: [
                      for (final w in WhoYouAre.values)
                        _Item(
                          key: 'who-${w.name}',
                          label: w.label,
                          hint: w.hint,
                          on: _whoNow == w,
                          onTap: () => setState(() {
                            _who = _whoNow == w ? null : w;
                            _whoTouched = true;
                          }),
                        ),
                    ],
                  ),
                  1 => _Picks(
                    items: [
                      for (final m in WhatMatters.values)
                        _Item(
                          key: 'matters-${m.name}',
                          label: m.label,
                          hint: m.hint,
                          on: _mattersNow.contains(m),
                          onTap: () => setState(
                            () => _matters = _toggle(_mattersNow, m),
                          ),
                        ),
                    ],
                  ),
                  _ => _Picks(
                    twoToARow: true,
                    items: [
                      for (final p in RegularPayment.values)
                        _Item(
                          key: 'pays-${p.name}',
                          label: p.label,
                          on: _paysNow.contains(p),
                          onTap: () =>
                              setState(() => _pays = _toggle(_paysNow, p)),
                        ),
                    ],
                  ),
                },
                const SizedBox(height: 20),
                SetupAction(
                  key: const Key('about-continue'),
                  label: 'Continue',
                  busy: _saving,
                  problem: _failed ? 'Your answers could not be saved.' : null,
                  onPressed: _next,
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('about-skip'),
                  onPressed: _saving
                      ? null
                      : () {
                          // Skip leaves this question's answer as it was.
                          setState(() {
                            switch (_step) {
                              case 0:
                                _whoTouched = false;
                              case 1:
                                _matters = null;
                              default:
                                _pays = null;
                            }
                          });
                          _next();
                        },
                  child: const Text('Skip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Set<T> _toggle<T>(Set<T> set, T item) =>
    set.contains(item) ? ({...set}..remove(item)) : {...set, item};

class _Item {
  const _Item({
    required this.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.hint,
  });

  final String key;
  final String label;
  final String? hint;
  final bool on;
  final VoidCallback onTap;
}

/// The answers in a card: each a row, picked ones in red with a check and
/// no fill. [twoToARow] sets them side by side while every word fits.
class _Picks extends StatelessWidget {
  const _Picks({
    required this.items,
    this.single = false,
    this.twoToARow = false,
  });

  final List<_Item> items;
  final bool single;
  final bool twoToARow;

  @override
  Widget build(BuildContext context) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        final style = Theme.of(context).textTheme.bodyLarge!;
        final scaler = MediaQuery.textScalerOf(context);
        final fits =
            twoToARow &&
            items.every(
              (i) => i.label.split(' ').every((word) {
                final painter = TextPainter(
                  text: TextSpan(text: word, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: scaler,
                )..layout();
                final width = painter.width;
                painter.dispose();
                // Padding on both sides and the check.
                return width <= half - 2 * Layout.cardPadding - 32;
              }),
            );
        Widget row(_Item item) => _PickRow(item, single: single);
        if (!fits) {
          return Column(
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0) const Divider(height: 1),
                row(item),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < items.length; i += 2) ...[
              if (i > 0) const Divider(height: 1),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: row(items[i])),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: i + 1 < items.length
                          ? row(items[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _PickRow extends StatelessWidget {
  const _PickRow(this.item, {required this.single});

  final _Item item;
  final bool single;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final ink = item.on ? colors.link : theme.colorScheme.onSurface;
    return MergeSemantics(
      child: Semantics(
        checked: item.on,
        inMutuallyExclusiveGroup: single,
        child: InkWell(
          key: Key(item.key),
          onTap: item.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Layout.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Layout.cardPadding,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.label,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: ink,
                            fontWeight: item.on ? FontWeight.w600 : null,
                          ),
                        ),
                        if (item.hint != null)
                          Text(item.hint!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Kept in place when not picked, so rows do not shift.
                  Icon(
                    Icons.check,
                    size: 20,
                    color: item.on ? colors.link : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
