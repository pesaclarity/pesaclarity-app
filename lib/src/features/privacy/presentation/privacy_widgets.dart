import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/consent.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../data/policy_source.dart';
import 'email_policy_sheet.dart';

/// The plain-language promises, each with a tick.
class PrivacyPromisesCard extends StatelessWidget {
  const PrivacyPromisesCard({this.counts = false, super.key});

  /// Whether the server's monthly counts are named (policy 2.4 on).
  final bool counts;

  static const promises = [
    'Your transactions, payees and debts stay on this phone.',
    'We store only your sign-in details and backups we cannot open.',
    'We never sell your data and never show ads.',
    'Delete your account any time; we erase it within 30 days.',
  ];

  /// The second promise once policy 2.4 is agreed (ADR 0024).
  static const countsPromise =
      'We store only your sign-in details, backups we cannot open and '
      'counts that name no one.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          children: [
            for (final promise in [
              promises[0],
              counts ? countsPromise : promises[1],
              ...promises.skip(2),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 12),
                      child: Icon(
                        Icons.check,
                        size: 18,
                        color: colors.successText,
                      ),
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
    'Learn from your corrections on this phone. Nothing is sent',
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

/// Consent switches in one card: [kinds], by default the two the app asks
/// about when the policy changes. Crash reports are asked about when one
/// happens (ADR 0024), so they are left out.
class ConsentSwitchesCard extends StatelessWidget {
  const ConsentSwitchesCard({
    required this.values,
    required this.onChanged,
    this.kinds = const [ConsentKind.improveApp, ConsentKind.licensedModels],
    super.key,
  });

  final List<ConsentKind> kinds;

  /// Null while loading, which disables the switches.
  final Map<ConsentKind, bool>? values;
  final void Function(ConsentKind kind, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = this.values;
    return Card(
      child: Column(
        children: [
          for (final (index, kind) in kinds.indexed) ...[
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
  if (opened) return;
  // No email app: a signed-in person can have the server send it.
  final session = ref.read(authControllerProvider).value;
  if (session != null && context.mounted) {
    await showEmailPolicySheet(
      context,
      policy,
      suggestedEmail: session.method == SignInMethod.email
          ? session.contact
          : null,
    );
    return;
  }
  if (context.mounted) {
    showNote(context, 'Set up an email app on this phone to send a copy.');
  }
}
