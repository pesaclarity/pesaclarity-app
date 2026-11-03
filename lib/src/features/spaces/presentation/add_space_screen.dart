import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/spaces_providers.dart';

/// Adds a space, such as a business, with its own encrypted data.
class AddSpaceScreen extends ConsumerStatefulWidget {
  const AddSpaceScreen({super.key});

  @override
  ConsumerState<AddSpaceScreen> createState() => _AddSpaceScreenState();
}

class _AddSpaceScreenState extends ConsumerState<AddSpaceScreen> {
  final _name = TextEditingController();
  var _kind = SpaceKind.business;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    await ref.read(spacesProvider.notifier).add(_name.text, _kind);
    // The new space reads no messages until its accounts are picked.
    router.go(AppRoutes.home);
    unawaited(router.push(AppRoutes.myAccounts));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final canAdd = _name.text.trim().isNotEmpty && !_saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a space')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              key: const Key('space-name'),
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'For example, Mama Mboga stall',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Kind', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<SpaceKind>(
              segments: [
                for (final kind in SpaceKind.values)
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.single),
            ),
            const SizedBox(height: 20),
            Text('Which money goes here?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Next, pick the accounts this space reads, such as a bank used '
              'only for the business. Any transaction can also be moved '
              'here by hand.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('space-add'),
              onPressed: canAdd ? _add : null,
              child: const Text('Add space'),
            ),
            const SizedBox(height: 8),
            Text(
              'It gets its own encrypted data and plan on this phone.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
