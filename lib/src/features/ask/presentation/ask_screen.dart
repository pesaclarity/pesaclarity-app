import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/ask_repository.dart';
import '../../../domain/ask/answer.dart';
import '../../../domain/ask/periods.dart';
import '../../../domain/ask/understanding.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/ask_providers.dart';
import '../application/ask_settings.dart';
import 'ask_answer_view.dart';
import 'ask_strings.dart';

/// Ask: a conversation about the open space's money.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({
    this.conversationId,
    this.categoryId,
    this.month,
    this.from,
    this.to,
    super.key,
  });

  /// A saved conversation to open; a new one when null.
  final int? conversationId;

  /// "Ask about this": the category and month to start on.
  final int? categoryId;
  final YearMonth? month;

  /// "Ask about Food, 1 to 27 Oct": the days to start on, both included.
  final CalendarDate? from;
  final CalendarDate? to;

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _hideStarters = false;

  AskController get _controller => ref.read(askControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (widget.conversationId != null) {
        return _controller.open(widget.conversationId!);
      }
      if (widget.categoryId != null ||
          widget.month != null ||
          widget.from != null) {
        return _controller.presetFor(
          categoryId: widget.categoryId,
          month: widget.month,
          from: widget.from,
          to: widget.to,
        );
      }
      _controller.startNew();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final question = text ?? _input.text;
    if (question.trim().isEmpty) return;
    _input.clear();
    await _controller.ask(question);
    _toEnd();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _open(AskAnswer answer) {
    final context = answer.context;
    final period = context.period;
    final category = context.entities[SlotKind.category]?.key;
    final route = switch (answer.link) {
      AskLink.activity => AppRoutes.activityWith(
        ActivityFilter(
          from: period?.from,
          to: period?.lastDay,
          categoryId: category != null && !category.contains('|')
              ? int.tryParse(category.substring(2))
              : null,
        ),
      ),
      AskLink.insights || AskLink.businessInsights => AppRoutes.insights,
      AskLink.debts => AppRoutes.debts,
      AskLink.goals => AppRoutes.goals,
      AskLink.bills => AppRoutes.plan,
      AskLink.stock => AppRoutes.stock,
      null => null,
    };
    if (route != null) this.context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final session = ref.watch(askControllerProvider);
    final space = ref.watch(activeSpaceProvider);
    final settings =
        ref.watch(askSettingsProvider).value ?? const AskSettings();
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final engine = ref.watch(askEngineProvider).value;
    final starters = engine?.starters ?? const <String>[];
    final tags = [
      for (final kind in [
        SlotKind.category,
        SlotKind.payee,
        SlotKind.item,
        SlotKind.account,
      ])
        if (session.context.entities[kind] case final e?) (kind, e.name),
      if (session.context.period case final p?)
        (
          SlotKind.period,
          p.kind == PeriodKind.month
              ? p.label(today).split(' ').first
              : p.label(today),
        ),
    ];
    final lastReply = session.messages.lastOrNull?.answer;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title ?? AskStrings.title,
              overflow: TextOverflow.ellipsis,
            ),
            if (session.title != null)
              Text(
                space.name,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('ask-conversations'),
            tooltip: AskStrings.conversations,
            icon: const Icon(Icons.menu),
            onPressed: () => context.push(AppRoutes.askConversations),
          ),
          if (session.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(space.name)),
            )
          else ...[
            IconButton(
              key: const Key('ask-new'),
              tooltip: AskStrings.newConversation,
              icon: const Icon(Icons.add),
              onPressed: _controller.startNew,
            ),
            IconButton(
              key: const Key('ask-menu'),
              tooltip: AskStrings.more,
              icon: const Icon(Icons.more_vert),
              onPressed: () => showAskMenu(context, ref),
            ),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (session.isEmpty)
                    _Empty(space: space.name)
                  else
                    ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        Layout.gutter,
                        8,
                        Layout.gutter,
                        Layout.cardGap,
                      ),
                      children: [
                        for (final (i, m) in session.messages.indexed)
                          if (m.role == AskRole.person)
                            QuestionBubble(m.text)
                          else if (m.answer != null) ...[
                            AnswerCard(
                              answer: m.answer!,
                              today: today,
                              charts: settings.charts,
                              onUpdate: () => _controller.update(i),
                              onSeeAll: () => _open(m.answer!),
                              onChoose: i == session.messages.length - 1
                                  ? (choice, period) async {
                                      await _controller.choose(
                                        m.answer!,
                                        choice,
                                        period: period,
                                      );
                                      _toEnd();
                                    }
                                  : null,
                            ),
                            if (i == session.messages.length - 1 &&
                                m.answer!.suggestions.isNotEmpty)
                              SuggestionChips(
                                m.answer!.suggestions,
                                onTap: _send,
                              ),
                          ],
                        if (session.busy)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              AskStrings.thinking,
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (session.isEmpty && !_hideStarters && starters.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 8,
                      child: _Starters(
                        starters,
                        onTap: _send,
                        onClose: () => setState(() => _hideStarters = true),
                      ),
                    ),
                ],
              ),
            ),
            if (tags.isNotEmpty && lastReply?.kind != ReplyKind.cant)
              _Tags(tags, onDrop: _controller.dropTag),
            _InputBar(
              controller: _input,
              hint: session.isEmpty
                  ? (space.kind == SpaceKind.personal
                        ? AskStrings.hint
                        : AskStrings.hintFor(space.name))
                  : AskStrings.followUpHint,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.space});

  final String space;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colors.brandSoft,
              child: Icon(
                Icons.chat_bubble_outline,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(AskStrings.emptyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              AskStrings.emptyBody(space),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating "Try asking" card above the box.
class _Starters extends StatelessWidget {
  const _Starters(this.starters, {required this.onTap, required this.onClose});

  final List<String> starters;
  final ValueChanged<String> onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return DecoratedBox(
      key: const Key('ask-starters'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AskStrings.tryAsking,
                    style: theme.textTheme.labelSmall!.copyWith(
                      color: colors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AskStrings.hideSuggestions,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
            for (final s in starters)
              InkWell(
                onTap: () => onTap(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags(this.tags, {required this.onDrop});

  final List<(SlotKind, String)> tags;
  final ValueChanged<SlotKind> onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return SingleChildScrollView(
      key: const Key('ask-tags'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Layout.gutter, 4, Layout.gutter, 4),
      child: Row(
        children: [
          Text(
            AskStrings.askingAbout,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          for (final (kind, name) in tags)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InputChip(
                key: Key('ask-tag-${kind.name}'),
                label: Text(name),
                backgroundColor: colors.brandSoft,
                side: BorderSide.none,
                deleteIcon: const Icon(Icons.close, size: 14),
                deleteButtonTooltipMessage: AskStrings.dropTag(name),
                onDeleted: () => onDrop(kind),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('ask-input'),
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton.filled(
                key: const Key('ask-send'),
                tooltip: AskStrings.send,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => onSend(controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The conversation's menu: rename, update, start anew, delete.
Future<void> showAskMenu(BuildContext context, WidgetRef ref) {
  final session = ref.read(askControllerProvider);
  final controller = ref.read(askControllerProvider.notifier);
  final danger = Theme.of(context).colorScheme.primary;
  return showAppSheet<void>(
    context: context,
    builder: (sheet) => SheetBody(
      title: session.title ?? AskStrings.title,
      subtitle: AskStrings.namedFromFirst,
      children: [
        const SizedBox(height: 8),
        ListTile(
          key: const Key('ask-rename'),
          contentPadding: EdgeInsets.zero,
          title: const Text(AskStrings.rename),
          onTap: () async {
            Navigator.of(sheet).pop();
            final title = await _askTitle(context, session.title ?? '');
            if (title != null) await controller.rename(title);
          },
        ),
        ListTile(
          key: const Key('ask-update-all'),
          contentPadding: EdgeInsets.zero,
          title: const Text(AskStrings.updateAll),
          onTap: () {
            Navigator.of(sheet).pop();
            controller.updateAll();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(AskStrings.startNew),
          onTap: () {
            Navigator.of(sheet).pop();
            controller.startNew();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(AskStrings.settings),
          onTap: () {
            Navigator.of(sheet).pop();
            context.push(AppRoutes.askSettings);
          },
        ),
        ListTile(
          key: const Key('ask-delete'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            AskStrings.deleteConversation,
            style: TextStyle(color: danger),
          ),
          onTap: () async {
            Navigator.of(sheet).pop();
            final sure = await confirmDelete(
              context,
              title: AskStrings.deleteConversationQuestion,
              body: AskStrings.deleteConversationBody,
            );
            if (sure) await controller.deleteConversation();
          },
        ),
      ],
    ),
  );
}

Future<String?> _askTitle(BuildContext context, String current) {
  final field = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text(AskStrings.renameTitle),
      content: TextField(
        key: const Key('ask-rename-field'),
        controller: field,
        autofocus: true,
        maxLength: 80,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text(AskStrings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(field.text),
          child: const Text(AskStrings.save),
        ),
      ],
    ),
  ).whenComplete(field.dispose);
}
