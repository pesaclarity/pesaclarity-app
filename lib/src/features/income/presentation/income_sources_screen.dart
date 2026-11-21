import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/income/income_sources.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../onboarding/presentation/setup_parts.dart';
import '../application/income_providers.dart';

/// "How does money usually come to you?": several answers, at setup and in
/// Profile.
class IncomeSourcesScreen extends ConsumerStatefulWidget {
  const IncomeSourcesScreen({this.onboarding = false, super.key});

  /// At setup, Continue goes on to My accounts; in Profile it goes back.
  final bool onboarding;

  @override
  ConsumerState<IncomeSourcesScreen> createState() =>
      _IncomeSourcesScreenState();
}

class _IncomeSourcesScreenState extends ConsumerState<IncomeSourcesScreen> {
  Set<IncomeSource>? _picked;
  var _saving = false;
  var _failed = false;

  Future<void> _continue(Set<IncomeSource> picked) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref.read(incomeSourcesProvider.notifier).choose(picked);
    } on Object catch (error) {
      debugPrint('How money comes in could not be saved: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    if (widget.onboarding) {
      context.go(AppRoutes.onboardingAccounts);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    // Only what is already read: answers saved earlier show once read, and
    // a read that fails or never ends keeps nobody from going on.
    final saved = ref.watch(incomeSourcesProvider).value;
    final picked = _picked ?? saved?.picked ?? const <IncomeSource>{};

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleIncomeSources,
          child: const Text('Your money'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'How does money usually come to you?',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose all that fit. Pesa Clarity plans around them, and learns '
              'from your messages too.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  for (final (i, source) in IncomeSource.values.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    // Merged so the id lands on the node that carries the
                    // checked state.
                    MergeSemantics(
                      child: Semantics(
                        identifier: SemanticIds.incomeSource(source.name),
                        child: CheckboxListTile(
                          key: Key('income-${source.name}'),
                          title: Text(source.label),
                          subtitle: Text(source.hint),
                          value: picked.contains(source),
                          onChanged: (on) => setState(
                            () => _picked = {
                              ...picked.where((s) => s != source),
                              if (on ?? false) source,
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SetupAction(
              identifier: SemanticIds.onboardingIncomeContinue,
              label: widget.onboarding ? 'Continue' : 'Save',
              busy: _saving,
              problem: _failed ? 'Your answer could not be saved.' : null,
              // In Profile, saving before the answers are read would drop
              // the ones not shown.
              onPressed: picked.isEmpty || (!widget.onboarding && saved == null)
                  ? null
                  : () => _continue(picked),
            ),
            const SizedBox(height: 8),
            Text(
              picked.isEmpty
                  ? 'Choose at least one to continue.'
                  : 'You can change this any time in Profile.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
