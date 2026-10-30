import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/privacy_policy.dart';
import '../../../theme/pesa_colors.dart';
import '../data/policy_source.dart';
import 'privacy_widgets.dart';

/// The full privacy policy bundled with the app, with its version and date.
class PolicyScreen extends ConsumerWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(privacyPolicyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: switch (policy) {
        AsyncData(:final value) => PolicyText(
          policy: value,
          footer: FilledButton.icon(
            onPressed: () => emailPolicyCopy(context, ref),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Email me a copy'),
          ),
        ),
        AsyncError() => const Center(
          child: Text('The policy could not be opened. Try again later.'),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

/// The terms bundled with the app, laid out like the privacy policy.
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Terms')),
      body: switch (terms) {
        AsyncData(:final value) => PolicyText(policy: value),
        AsyncError() => const Center(
          child: Text('The terms could not be opened. Try again later.'),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

/// The policy's blocks laid out for reading.
class PolicyText extends StatelessWidget {
  const PolicyText({required this.policy, this.footer, super.key});

  final PrivacyPolicy policy;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = PesaColors.of(context).textMuted;
    final body = theme.textTheme.bodyLarge;

    Widget block(PolicyBlock block) => switch (block.type) {
      PolicyBlockType.heading => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(block.text, style: theme.textTheme.titleMedium),
      ),
      PolicyBlockType.paragraph => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(block.text, style: body),
      ),
      PolicyBlockType.term => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          block.text,
          style: body!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      PolicyBlockType.bullet => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 10, left: 4),
              child: Icon(Icons.circle, size: 6, color: muted),
            ),
            Expanded(child: Text(block.text, style: body)),
          ],
        ),
      ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(policy.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          policy.versionLine,
          style: theme.textTheme.bodyMedium!.copyWith(color: muted),
        ),
        for (final b in policy.blocks) block(b),
        if (footer != null) ...[const SizedBox(height: 24), footer!],
      ],
    );
  }
}

/// Shows the full policy over the current screen.
Future<void> showPolicy(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push<void>(MaterialPageRoute(builder: (_) => const PolicyScreen()));
