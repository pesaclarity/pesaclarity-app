import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/flavor.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';

/// Email with a 6-digit code, and Google on Play builds. Calls [onSignedIn]
/// once the account is ready.
class SignInPanel extends ConsumerStatefulWidget {
  const SignInPanel({required this.onSignedIn, super.key});

  final VoidCallback onSignedIn;

  @override
  ConsumerState<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends ConsumerState<SignInPanel> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  EmailChallenge? _challenge;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    final challenge = await _auth.startEmailSignIn(_email.text);
    if (!mounted) return;
    _code.clear();
    setState(() => _challenge = challenge);
  });

  Future<void> _verify() => _run(() async {
    await _auth.verifyEmailCode(_challenge!, _code.text);
    if (mounted) widget.onSignedIn();
  });

  Future<void> _google() => _run(() async {
    final signedIn = await _auth.signInWithGoogle();
    if (signedIn && mounted) widget.onSignedIn();
  });

  void _changeEmail() => setState(() {
    _challenge = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: challenge == null ? _emailStep(context) : _codeStep(challenge),
    );
  }

  Widget _emailStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final flavor = ref.watch(appFlavorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'Email',
            style: theme.textTheme.labelLarge!.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _email,
          hint: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          inputFormatters: [LengthLimitingTextInputFormatter(254)],
          onSubmitted: (_) => _sendCode(),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 12),
        _PillButton.filled(
          label: 'Send code',
          busy: _busy,
          onPressed: _sendCode,
        ),
        if (flavor.allowsGoogleServices) ...[
          const SizedBox(height: 12),
          _OrDivider(),
          const SizedBox(height: 12),
          _PillButton.outlined(
            label: 'Continue with Google',
            leading: const _GoogleMark(),
            onPressed: _busy ? null : _google,
          ),
        ],
      ],
    );
  }

  Widget _codeStep(EmailChallenge challenge) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'Enter the code sent to ${challenge.email}',
            style: theme.textTheme.labelLarge!.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _code,
          hint: '6-digit code',
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          autofocus: true,
          onSubmitted: (_) => _verify(),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 12),
        _PillButton.filled(label: 'Verify', busy: _busy, onPressed: _verify),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy ? null : _changeEmail,
              child: const Text('Change email'),
            ),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Send a new code'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PillField extends StatelessWidget {
  const _PillField({
    required this.controller,
    required this.hint,
    required this.keyboardType,
    required this.inputFormatters,
    required this.onSubmitted,
    this.autofillHints,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String> onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
      borderSide: BorderSide(color: color),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      autofocus: autofocus,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: border(colors.border),
        enabledBorder: border(colors.border),
        focusedBorder: border(theme.colorScheme.primary),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton.filled({
    required this.label,
    required this.onPressed,
    this.busy = false,
  }) : outlined = false,
       leading = null;

  const _PillButton.outlined({
    required this.label,
    required this.onPressed,
    this.leading,
  }) : outlined = true,
       busy = false;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outlined;
  final Widget? leading;

  static const _height = 54.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(_height),
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          textStyle: theme.textTheme.bodyLarge!.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(_height),
        textStyle: theme.textTheme.bodyLarge!.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Working',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Text(label),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: colors.textMuted),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// The plain "G" mark from the design; Google's logo needs brand approval.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.textMuted, width: 2),
        ),
        child: Text(
          'G',
          style: Theme.of(context).textTheme.labelSmall!
              .copyWith(fontWeight: FontWeight.w700, color: colors.textMuted),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: theme.textTheme.bodySmall!.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
