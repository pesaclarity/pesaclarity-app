import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/privacy_policy.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';

/// "Email me a copy" for a phone with no email app: the server sends the
/// policy, as text and a PDF, to the address given. Signed-in people only.
Future<void> showEmailPolicySheet(
  BuildContext context,
  PrivacyPolicy policy, {
  String? suggestedEmail,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      EmailPolicySheet(policy: policy, suggestedEmail: suggestedEmail),
);

class EmailPolicySheet extends ConsumerStatefulWidget {
  const EmailPolicySheet({
    required this.policy,
    this.suggestedEmail,
    super.key,
  });

  final PrivacyPolicy policy;
  final String? suggestedEmail;

  @override
  ConsumerState<EmailPolicySheet> createState() => _EmailPolicySheetState();
}

class _EmailPolicySheetState extends ConsumerState<EmailPolicySheet> {
  late final _email = TextEditingController(text: widget.suggestedEmail);
  var _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  static String _message(AuthFailure failure) => switch (failure.kind) {
    AuthFailureKind.invalidEmail =>
      'Enter your email address, for example name@example.com.',
    AuthFailureKind.rateLimited =>
      "You have had today's copies. Try again tomorrow.",
    AuthFailureKind.unavailable => 'Emailed copies arrive in a later update.',
    AuthFailureKind.network =>
      'Could not reach Pesa Clarity. Check your connection and try again.',
    AuthFailureKind.sessionEnded => 'You were signed out. Sign in again.',
    _ => 'Could not send it this time. Try again.',
  };

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .emailPolicyCopy(
            email: _email.text.trim(),
            policy: widget.policy.source,
          );
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _message(failure);
        });
      }
      return;
    }
    navigator.pop();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Sent. Check your inbox for the copy.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final canSend = _email.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Email me a copy', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'There is no email app on this phone, so we can send the '
              'privacy policy for you, as text and a PDF.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('email-policy-address'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Send it to',
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We use this address once, to send the copy, and do not keep '
              'it.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('email-policy-send'),
              onPressed: canSend ? _send : null,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
