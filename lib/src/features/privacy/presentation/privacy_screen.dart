import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/privacy/consent.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/consent_controller.dart';
import '../data/policy_source.dart';
import 'privacy_widgets.dart';

/// Privacy, under Profile: promises, consent switches and the full policy.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(consentControllerProvider).value;
    final policy = ref.watch(privacyPolicyProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const PrivacySectionLabel('In plain words'),
          const PrivacyPromisesCard(),
          const SizedBox(height: 24),
          const PrivacySectionLabel('Your choices'),
          ConsentSwitchesCard(
            values: record == null
                ? null
                : {for (final k in ConsentKind.values) k: record.valueOf(k)},
            onChanged: (kind, value) => ref
                .read(consentControllerProvider.notifier)
                .setChoice(kind, value),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.privacyPolicy),
            child: const Text('Read the full privacy policy'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: policy == null
                ? null
                : () => emailPolicyCopy(context, ref),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Email me a copy'),
          ),
          if (policy != null) ...[
            const SizedBox(height: 12),
            Text(
              policy.versionLine,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
