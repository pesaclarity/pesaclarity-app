import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import 'sign_in_panel.dart';

/// Sign in later, from Profile.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'An account lets you back up to the Pesa Clarity vault and '
            'restore on a new phone. Your money data stays on this phone.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 24),
          SignInPanel(
            onSignedIn: () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Signed in')));
              context.go(AppRoutes.profile);
            },
          ),
        ],
      ),
    );
  }
}
