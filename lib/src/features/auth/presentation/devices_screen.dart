import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';

/// Phones signed in to the account, with remote sign-out for the others.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  late Future<List<SignedInDevice>> _devices;
  final _signingOut = <String>{};

  @override
  void initState() {
    super.initState();
    _devices = _load();
  }

  Future<List<SignedInDevice>> _load() =>
      ref.read(authControllerProvider.notifier).devices();

  void _reload() {
    setState(() {
      _devices = _load();
    });
  }

  Future<void> _signOut(SignedInDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign out ${device.name}?'),
        content: const Text(
          'That phone loses access to your account and backups straight '
          'away. Data already on it stays there, protected by its app lock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOut.add(device.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signOutDevice(device.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${device.name} is signed out')),
      );
    } on AuthFailure catch (failure) {
      // Already gone counts as done; the reload shows the current list.
      if (failure.kind != AuthFailureKind.notFound) {
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _signingOut.remove(device.id));
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Signed-in phones')),
      body: FutureBuilder<List<SignedInDevice>>(
        future: _devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Loading'),
            );
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error is AuthFailure
                          ? error.message
                          : const AuthFailure(AuthFailureKind.server).message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    if (error is! AuthFailure ||
                        error.kind != AuthFailureKind.sessionEnded)
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Try again'),
                      ),
                  ],
                ),
              ),
            );
          }
          final devices = [...snapshot.data!]
            ..sort((a, b) {
              if (a.current != b.current) return a.current ? -1 : 1;
              return b.lastSeenAt.compareTo(a.lastSeenAt);
            });
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'Sign out a phone you no longer use or have lost. It loses '
                'access to your backups on its next request.',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    for (final (index, device) in devices.indexed) ...[
                      if (index > 0) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.smartphone_outlined),
                        title: Text(device.name),
                        subtitle: Text(
                          device.current
                              ? 'This phone'
                              : 'Last active ${formatDeviceDate(device.lastSeenAt)}',
                        ),
                        trailing: device.current
                            ? null
                            : _signingOut.contains(device.id)
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: () => _signOut(device),
                                child: const Text('Sign out'),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a server time as a local date, such as "3 Oct 2026".
String formatDeviceDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}
