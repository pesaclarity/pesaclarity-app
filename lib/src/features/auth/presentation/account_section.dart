import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../theme/pesa_colors.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';

/// Profile's top card: who is signed in, or an offer to sign in.
class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final session = ref.watch(authControllerProvider).value;

    final String title;
    final String subtitle;
    if (session == null) {
      title = 'Using without an account';
      subtitle = 'Sign in to back up to the vault and restore on a new phone.';
    } else {
      final how = switch (session.method) {
        SignInMethod.google => 'Signed in with Google',
        SignInMethod.email => session.contact ?? 'Signed in with your email',
        null => 'Signed in',
      };
      title = session.displayName ?? how;
      subtitle = session.displayName == null
          ? 'Your account is used for sign-in and backups.'
          : how;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: session?.displayName, signedIn: session != null),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (session == null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.signIn),
                child: const Text('Sign in'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.signedIn});

  final String? name;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = PesaColors.of(context);
    final initials = initialsOf(name);
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 28,
        backgroundColor: signedIn ? scheme.primary : colors.brandSoft,
        foregroundColor: signedIn ? scheme.onPrimary : scheme.primary,
        child: initials == null
            ? const Icon(Icons.person_outline)
            : Text(
                initials,
                style: Theme.of(context).textTheme.titleMedium!
                    .copyWith(color: scheme.onPrimary),
              ),
      ),
    );
  }
}

/// Up to two initials from [name], such as "JK" for "John Kamau".
String? initialsOf(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final letters = [
    parts.first.characters.first,
    if (parts.length > 1) parts.last.characters.first,
  ];
  return letters.join().toUpperCase();
}

/// Profile's account rows and actions, shown only when signed in.
class AccountActions extends ConsumerStatefulWidget {
  const AccountActions({super.key});

  @override
  ConsumerState<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends ConsumerState<AccountActions> {
  bool _busy = false;

  Future<void> _signOut() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final confirmed = await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          confirmed
              ? 'Signed out. Your data on this phone stays here.'
              : 'Signed out on this phone. To remove it from your account, '
                    'sign it out from another phone under Signed-in phones.',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Account deleted. Your data on this phone stays here.'),
        ),
      );
    } on AuthFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    if (session == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final colors = PesaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Signed-in phones'),
            subtitle: const Text('See them and sign out the ones you lost'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.devices),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                ),
                onPressed: _busy ? null : _signOut,
                child: const Text('Sign out'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: colors.brandSoft,
                  foregroundColor: colors.link,
                  side: BorderSide(color: scheme.primary.withAlpha(60)),
                ),
                onPressed: _busy ? null : _delete,
                child: const Text('Delete account'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog.adaptive(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This removes, straight away and for good:'),
          const SizedBox(height: 8),
          for (final item in const [
            'your account and sign-in details',
            'the list of signed-in phones and your sign-in history',
            'every backup kept in the Pesa Clarity vault',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $item'),
            ),
          const SizedBox(height: 8),
          Text(
            'Your money data on this phone stays here, and you can keep '
            'using the app without an account. '
            '${isCupertino(context) ? 'Backups saved to Files stay too.' : 'Backups saved to your own Google Drive or SD card stay too.'}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        DialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        DialogAction(
          destructive: true,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
