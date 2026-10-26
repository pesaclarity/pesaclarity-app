import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/consent.dart';
import '../../../domain/privacy/privacy_policy.dart';
import '../../../theme/pesa_colors.dart';
import '../application/consent_controller.dart';
import '../data/policy_source.dart';
import 'policy_screen.dart';
import 'privacy_widgets.dart';

/// Asks again after the privacy policy changes: what changed, the choices,
/// and agreeing to the new version.
class PolicyReviewScreen extends ConsumerStatefulWidget {
  const PolicyReviewScreen({required this.changes, super.key});

  /// Changes since the version last agreed to, newest first.
  final List<PolicyChange> changes;

  @override
  ConsumerState<PolicyReviewScreen> createState() => _PolicyReviewScreenState();
}

class _PolicyReviewScreenState extends ConsumerState<PolicyReviewScreen> {
  Map<ConsentKind, bool>? _values;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = PesaColors.of(context).textMuted;
    final record = ref.watch(consentControllerProvider).value;
    final policy = ref.watch(privacyPolicyProvider).value;
    final values = _values ??= record == null
        ? null
        : {for (final k in ConsentKind.values) k: record.valueOf(k)};

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Our privacy policy changed', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Here is what changed. Check your choices, then agree to carry on. '
            'Optional uses of your data stay paused until you do.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const PrivacySectionLabel('What changed'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final change in widget.changes) ...[
                    Text(
                      'Version ${change.version} · '
                      '${formatPolicyDate(change.date)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final item in change.items)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, right: 10),
                              child: Icon(Icons.circle, size: 6, color: muted),
                            ),
                            Expanded(
                              child: Text(
                                item,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const PrivacySectionLabel('Your choices'),
          ConsentSwitchesCard(
            values: values,
            onChanged: (kind, value) =>
                setState(() => _values = {...?_values, kind: value}),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => showPolicy(context),
            child: const Text('Read the full privacy policy'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: policy == null || values == null || _saving
                ? null
                : () => _agree(policy, values),
            child: const Text('Agree and continue'),
          ),
          if (policy != null) ...[
            const SizedBox(height: 12),
            Text(
              policy.versionLine,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _agree(
    PrivacyPolicy policy,
    Map<ConsentKind, bool> values,
  ) async {
    setState(() => _saving = true);
    await ref
        .read(consentControllerProvider.notifier)
        .accept(policy, values: values);
    if (mounted) Navigator.of(context).pop();
  }
}

bool _reviewShowing = false;

/// Shows [PolicyReviewScreen] over the app, once at a time.
Future<void> showPolicyReview(
  BuildContext context,
  List<PolicyChange> changes,
) async {
  if (_reviewShowing) return;
  _reviewShowing = true;
  try {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PolicyReviewScreen(changes: changes),
      ),
    );
  } finally {
    _reviewShowing = false;
  }
}
