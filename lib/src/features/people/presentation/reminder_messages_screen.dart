import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/people/reminder_text.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../reminders/application/business_reminders.dart';
import '../../reminders/application/reminders_controller.dart';

/// Reminder messages: the business's templates, the app to send with, the
/// till to pay to, and the daily nudge of who is due.
class ReminderMessagesScreen extends ConsumerWidget {
  const ReminderMessagesScreen({super.key});

  Future<void> _save(WidgetRef ref, ReminderSetup next) =>
      ref.read(reminderSetupProvider.notifier).save(next);

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ReminderSetup setup, {
    ReminderTemplate? template,
  }) async {
    final result = await showAdaptiveDialog<_Edited>(
      context: context,
      builder: (context) => _TemplateDialog(
        template: template,
        // Remind always keeps one message to offer.
        canDelete: template != null && setup.templates.length > 1,
      ),
    );
    switch (result) {
      case null:
        return;
      case _Delete():
        if (context.mounted) await _delete(context, ref, setup, template!);
      case _Save(template: final saved):
        final exists = setup.templates.any((t) => t.id == saved.id);
        await _save(
          ref,
          setup.copyWith(
            templates: exists
                ? [
                    for (final t in setup.templates)
                      t.id == saved.id ? saved : t,
                  ]
                : [...setup.templates, saved],
          ),
        );
    }
  }

  /// Deletes [template] once the owner confirms.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ReminderSetup setup,
    ReminderTemplate template,
  ) async {
    final yes = await confirmDelete(
      context,
      title: 'Delete ${template.name}?',
      body: 'Remind stops offering this message.',
    );
    if (!yes) return;
    await _save(
      ref,
      setup.copyWith(
        templates: [
          for (final x in setup.templates)
            if (x.id != template.id) x,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final loaded = ref.watch(reminderSetupProvider);
    final setup = loaded.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder messages'),
        actions: [
          if (setup != null)
            AddButton(
              key: const Key('add-message'),
              tooltip: 'Add a message',
              onPressed: () => _edit(context, ref, setup),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: loaded.hasError && !loaded.hasValue
          ? ErrorView(
              'Your reminder messages could not load.',
              onRetry: () => ref.invalidate(reminderSetupProvider),
            )
          : setup == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  'Fields fill in on their own: {name}, {amount}, {what}, '
                  '{due}, {date}, {business} and {till}. A sentence whose '
                  'field is empty is left out.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final (i, t) in setup.templates.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          key: Key('message-${t.id}'),
                          title: Text(t.name),
                          subtitle: Text(
                            t.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _edit(context, ref, setup, template: t),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Send reminders with',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                AdaptiveSegmented<SendWith>(
                  key: const Key('reminders-send-with'),
                  segments: [for (final s in SendWith.values) (s, s.label)],
                  selected: setup.sendWith,
                  segmentKey: (s) => Key('reminders-send-with-${s.name}'),
                  onChanged: (s) => _save(ref, setup.copyWith(sendWith: s)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Each customer can have their own, set when you remind them.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _TillField(
                  initial: setup.till ?? '',
                  onSaved: (till) => _save(
                    ref,
                    setup.copyWith(till: () => till.isEmpty ? null : till),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        key: const Key('nudge'),
                        title: const Text('Tell me who is due each day'),
                        subtitle: const Text(
                          'A notification on this phone, with Remind all',
                        ),
                        value: setup.nudge,
                        onChanged: (on) async {
                          // The nudge is a reminder, so reminders go on.
                          if (on) {
                            await ref
                                .read(remindersControllerProvider.notifier)
                                .setEnabled(true);
                          }
                          await _save(ref, setup.copyWith(nudge: on));
                        },
                      ),
                      if (setup.nudge)
                        ListTile(
                          title: const Text('At'),
                          trailing: Text(
                            TimeOfDay(
                              hour: setup.nudgeHour,
                              minute: setup.nudgeMinute,
                            ).format(context),
                          ),
                          onTap: () async {
                            final picked = await pickTime(
                              context,
                              initialTime: TimeOfDay(
                                hour: setup.nudgeHour,
                                minute: setup.nudgeMinute,
                              ),
                            );
                            if (picked == null) return;
                            await _save(
                              ref,
                              setup.copyWith(
                                nudgeHour: picked.hour,
                                nudgeMinute: picked.minute,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Reminders open WhatsApp or your SMS app with the message '
                  'filled in. You always tap send; this app sends nothing.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
    );
  }
}

class _TillField extends StatefulWidget {
  const _TillField({required this.initial, required this.onSaved});

  final String initial;
  final ValueChanged<String> onSaved;

  @override
  State<_TillField> createState() => _TillFieldState();
}

class _TillFieldState extends State<_TillField> {
  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSaved(_controller.text.trim());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('till'),
    controller: _controller,
    focusNode: _focus,
    keyboardType: TextInputType.text,
    onSubmitted: (t) => widget.onSaved(t.trim()),
    decoration: const InputDecoration(
      labelText: 'Till or Paybill for {till}',
      helperText: 'Such as 000000, or Paybill 000000 account 123',
    ),
  );
}

/// How the message dialog ends: saved, or deleted.
sealed class _Edited {
  const _Edited();
}

class _Save extends _Edited {
  const _Save(this.template);

  final ReminderTemplate template;
}

class _Delete extends _Edited {
  const _Delete();
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({this.template, this.canDelete = false});

  final ReminderTemplate? template;

  /// Offers Delete, for a message that is not the only one.
  final bool canDelete;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _text = TextEditingController(text: widget.template?.text ?? '');

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(widget.template == null ? 'Add a message' : 'Edit message'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('message-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('message-text'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
        ],
      ),
    ),
    actions: [
      if (widget.canDelete)
        DialogAction(
          key: const Key('message-delete'),
          destructive: true,
          onPressed: () => Navigator.of(context).pop(const _Delete()),
          child: const Text('Delete'),
        ),
      DialogAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      DialogAction(
        key: const Key('message-save'),
        onPressed: () {
          final name = _name.text.trim();
          final text = _text.text.trim();
          if (name.isEmpty || text.isEmpty) return;
          Navigator.of(context).pop(
            _Save(
              widget.template?.copyWith(name: name, text: text) ??
                  ReminderTemplate(
                    id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                    name: name,
                    text: text,
                  ),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
