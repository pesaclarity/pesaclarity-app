import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/layout.dart';
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
    // The new space reads no messages until its accounts are picked. A
    // business then says what it sells and starts its records (underneath).
    router.go(AppRoutes.home);
    if (_kind == SpaceKind.business) {
      unawaited(router.push(AppRoutes.whatYouSell));
    }
    unawaited(router.push(AppRoutes.chooseAccounts));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final groupLabel = theme.textTheme.bodyMedium!.copyWith(
      color: colors.textMuted,
    );
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
                hintText: 'Vegetable stall',
              ),
            ),
            const SizedBox(height: 8),
            Text('Kind', style: groupLabel),
            const SizedBox(height: Layout.cardGap),
            Card(
              child: RadioGroup<SpaceKind>(
                groupValue: _kind,
                onChanged: (v) => setState(() => _kind = v ?? _kind),
                child: Column(
                  children: [
                    for (final (i, kind) in SpaceKind.values.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      RadioListTile<SpaceKind>(
                        key: Key('space-kind-${kind.name}'),
                        value: kind,
                        title: Text(kind.label),
                        subtitle: Text(kind.hint),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Which money goes here?', style: groupLabel),
            const SizedBox(height: 4),
            Text(
              'Next, choose the accounts this space reads, such as a bank '
              'used only for it. Any transaction can also be moved here by '
              'hand.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('space-add'),
              onPressed: canAdd ? _add : null,
              child: const Text('Add a space'),
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
