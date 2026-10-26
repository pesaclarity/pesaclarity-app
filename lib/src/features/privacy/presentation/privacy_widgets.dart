import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/consent.dart';
import '../../../theme/pesa_colors.dart';
import '../data/policy_source.dart';

/// A small capitalised label above a group of cards, such as `YOUR CHOICES`.
class PrivacySectionLabel extends StatelessWidget {
  const PrivacySectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
        color: PesaColors.of(context).textMuted,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// The plain-language promises, each with a tick.
class PrivacyPromisesCard extends StatelessWidget {
  const PrivacyPromisesCard({super.key});

  static const promises = [
    'Your transactions, payees and debts stay on this phone.',
    'We store only your sign-in details and backups we cannot open.',
    'We never sell your data and never show ads.',
    'Delete your account any time; we erase it within 30 days.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
        child: Column(
          children: [
            for (final promise in promises)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 12),
                      child: Icon(Icons.check, size: 18, color: colors.success),
                    ),
                    Expanded(
                      child: Text(promise, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Title and description of each consent switch.
const consentLabels = {
  ConsentKind.improveApp: (
    'Help improve the app',
    'Share anonymous model updates, never your data',
  ),
  ConsentKind.licensedModels: (
    'Contribute to licensed models',
    'Pattern-only models, privacy-protected. Off by default',
  ),
  ConsentKind.crashReports: (
    'Send crash reports',
    'Anonymous, no financial details',
  ),
};

/// The three consent switches in one card.
class ConsentSwitchesCard extends StatelessWidget {
  const ConsentSwitchesCard({
    required this.values,
    required this.onChanged,
    super.key,
  });

  /// Null while loading, which disables the switches.
  final Map<ConsentKind, bool>? values;
  final void Function(ConsentKind kind, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = this.values;
    return Card(
      child: Column(
        children: [
          for (final (index, kind) in ConsentKind.values.indexed) ...[
            if (index > 0) const Divider(height: 1),
            CheckboxListTile(
              title: Text(consentLabels[kind]!.$1),
              subtitle: Text(consentLabels[kind]!.$2),
              value: values?[kind] ?? kind.defaultValue,
              onChanged: values == null
                  ? null
                  : (value) => onChanged(kind, value ?? false),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the person's email app with the bundled policy as a draft.
Future<void> emailPolicyCopy(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final policy = await ref.read(privacyPolicyProvider.future);
  var opened = false;
  try {
    opened = await ref
        .read(policyMailerProvider)
        .compose(
          subject: 'Pesa Clarity privacy policy, version ${policy.version}',
          body: policy.toPlainText(),
        );
  } on Exception {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Set up an email app on this phone to send a copy.'),
      ),
    );
  }
}
