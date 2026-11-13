import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/ask_repository.dart';
import '../../../domain/ask/answer.dart';
import '../../../domain/ask/context.dart';
import '../../../domain/ask/data_source.dart';
import '../../../domain/ask/engine.dart';
import '../../../domain/ask/matcher.dart';
import '../../../domain/ask/model_question_reader.dart';
import '../../../domain/ask/periods.dart';
import '../../../domain/ask/reply_writer.dart';
import '../../../domain/ask/rule_question_reader.dart';
import '../../../domain/ask/understanding.dart';
import '../../../domain/time/calendar.dart';
import '../../categoriser/data/tflite_flutter_runtime.dart';
import '../../spaces/application/spaces_providers.dart';
import '../data/app_ask_data_source.dart';
import '../data/ask_model_store.dart';
import 'ask_settings.dart';

/// Opens `ask-reader.tflite`. Its outputs have the message reader's shapes
/// (per-token labels, then whole-question labels), so the same TFLite
/// runtime runs it. Override with null for a build without TFLite, or with
/// a fake in tests.
final askReaderRuntimeOpenerProvider = Provider<AskReaderRuntimeOpener?>(
  (ref) =>
      (bytes) => _AskTfliteRuntime(TfliteReaderRuntime.open(bytes)),
);

class _AskTfliteRuntime implements AskReaderRuntime {
  _AskTfliteRuntime(this._runtime);

  final TfliteReaderRuntime _runtime;

  @override
  (List<List<double>>, List<double>) run(List<int> input) =>
      _runtime.run(input);

  @override
  void close() => _runtime.close();
}

/// Reads bundled model files; null when absent.
final askAssetReaderProvider = Provider<AssetReader>(
  (ref) => (path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  },
);

/// The trained question reader when bundled, else the rules.
final questionReaderProvider = FutureProvider<QuestionReader>((ref) async {
  final clock = ref.watch(clockProvider);
  final reader = await loadAskReader(
    readAsset: ref.watch(askAssetReaderProvider),
    openRuntime: ref.watch(askReaderRuntimeOpenerProvider),
    fallback: RuleQuestionReader(today: () => CalendarDate.local(clock())),
  );
  ref.onDispose(reader.close);
  return reader;
});

/// Writes reply sentences. A trained writer (`ask-writer.tflite`) goes here
/// wrapped in [CheckedReplyWriter], once its spec is settled.
final replyWriterProvider = Provider<ReplyWriter>(
  (ref) => const TemplateReplyWriter(),
);

/// What Ask reads, from the open space only.
final askDataSourceProvider = Provider<AskDataSource>((ref) {
  ref.watch(activeSpaceIdProvider);
  return AppAskDataSource(ref);
});

final askEngineProvider = FutureProvider<AskEngine>((ref) async {
  final reader = await ref.watch(questionReaderProvider.future);
  return AskEngine(
    source: ref.watch(askDataSourceProvider),
    reader: reader,
    writer: ref.watch(replyWriterProvider),
    spaceKind: ref.watch(activeSpaceProvider).kind,
  );
});

/// Saved conversations in the open space, newest first.
final askConversationsProvider = StreamProvider<List<AskConversation>>(
  (ref) => ref.watch(askRepositoryProvider).watchConversations(),
);

/// The conversation on screen.
class AskSession {
  const AskSession({
    this.conversationId,
    this.title,
    this.messages = const [],
    this.context = AskContext.empty,
    this.busy = false,
    this.lastAt,
  });

  final int? conversationId;
  final String? title;
  final List<AskMessage> messages;
  final AskContext context;
  final bool busy;

  /// When the person last asked; after [AskContext.idle] the next question
  /// starts afresh.
  final DateTime? lastAt;

  bool get isEmpty => messages.isEmpty;

  AskSession copyWith({
    int? conversationId,
    String? title,
    List<AskMessage>? messages,
    AskContext? context,
    bool? busy,
    DateTime? lastAt,
  }) => AskSession(
    conversationId: conversationId ?? this.conversationId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    context: context ?? this.context,
    busy: busy ?? this.busy,
    lastAt: lastAt ?? this.lastAt,
  );
}

/// Asks, answers and keeps the conversation, in the open space.
class AskController extends Notifier<AskSession> {
  @override
  AskSession build() {
    // A new space starts a new conversation.
    ref.watch(activeSpaceIdProvider);
    Future.microtask(_purge);
    return const AskSession();
  }

  AskRepository get _repo => ref.read(askRepositoryProvider);

  DateTime get _now => ref.read(clockProvider)();

  Future<AskSettings> get _settings => ref.read(askSettingsProvider.future);

  Future<void> _purge() async {
    try {
      final keep = (await _settings).keepFor.duration;
      if (keep != null) await _repo.purgeBefore(_now.subtract(keep));
    } on Object {
      // A failed tidy-up is tried again next time.
    }
  }

  /// Starts afresh, optionally about [context] (from "Ask about this").
  void startNew({AskContext context = AskContext.empty}) =>
      state = AskSession(context: context, lastAt: _now);

  /// Starts afresh about a category and month, from "Ask about this".
  Future<void> presetFor({
    int? categoryId,
    YearMonth? month,
    CalendarDate? from,
    CalendarDate? to,
  }) async {
    AskEntity? category;
    if (categoryId != null) {
      for (final e in await ref.read(askDataSourceProvider).entities()) {
        if (e.key == 'c:$categoryId') category = e;
      }
    }
    final now = _now;
    final today = CalendarDate.local(now);
    AskPeriod? period;
    if (month != null) {
      period = AskPeriod.month(month, today);
    } else if (from != null) {
      final last = to ?? today;
      final whole =
          from == from.yearMonth.firstDay &&
          from.yearMonth == last.yearMonth &&
          (last == from.yearMonth.lastDay || last == today);
      period = whole
          ? AskPeriod.month(from.yearMonth, today)
          : AskPeriod(
              PeriodKind.range,
              from,
              last.addDays(1),
              length: from.daysUntil(last) + 1,
            );
    }
    startNew(
      context: AskContext(
        intent: AskIntent.spent,
        entities: {SlotKind.category: ?category},
        period: period,
        at: now,
      ),
    );
  }

  /// Opens saved conversation [id].
  Future<void> open(int id) async {
    final conversation = await _repo.conversation(id);
    if (conversation == null) return startNew();
    state = AskSession(
      conversationId: id,
      title: conversation.title,
      messages: await _repo.messages(id),
      context: conversation.context,
      lastAt: conversation.updatedAt,
    );
  }

  Future<void> ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    final now = _now;
    final mine = AskMessage(role: AskRole.person, text: text, createdAt: now);
    state = state.copyWith(messages: [...state.messages, mine], busy: true);
    try {
      final engine = await ref.read(askEngineProvider.future);
      final context =
          state.lastAt != null &&
              now.difference(state.lastAt!) >= AskContext.idle
          ? AskContext.empty
          : state.context;
      final turn = await engine.ask(text, context: context, now: now);
      await _record(
        AskMessage(
          role: AskRole.person,
          text: text,
          createdAt: now,
          understanding: turn.understanding,
        ),
        turn,
        now,
        replaceLast: true,
      );
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// The person picked [choice] (null for all of them) for [clarify].
  Future<void> choose(
    AskAnswer clarify,
    AskEntity? choice, {
    AskPeriod? period,
  }) async {
    final now = _now;
    final engine = await ref.read(askEngineProvider.future);
    final word = clarify.clarifyWord;
    if (choice != null && word != null && (await _settings).save) {
      await _repo.learn(word, choice, now);
    }
    final turn = await engine.resolve(
      clarify,
      choice: choice,
      period: period,
      now: now,
    );
    final label = choice?.name ?? AskEngine.both(clarify.choices).name;
    await _record(
      AskMessage(role: AskRole.person, text: label, createdAt: now),
      turn,
      now,
    );
  }

  /// Drops the [kind] tag and answers again without it.
  Future<void> dropTag(SlotKind kind) async {
    final now = _now;
    final context = state.context.without(kind, now);
    final engine = await ref.read(askEngineProvider.future);
    final answer = await engine.run(context, now);
    await _record(
      null,
      AskTurn(
        Understanding(context.intent ?? AskIntent.spent),
        context,
        answer,
      ),
      now,
    );
  }

  /// Works out reply [index]'s numbers again.
  Future<void> update(int index) async {
    final message = state.messages[index];
    final old = message.answer;
    if (old == null || !old.canUpdate) return;
    final engine = await ref.read(askEngineProvider.future);
    final fresh = await engine.run(old.context, _now);
    final messages = [...state.messages]..[index] = message.withAnswer(fresh);
    state = state.copyWith(messages: messages);
    if (message.id != null) await _repo.replaceAnswer(message.id!, fresh);
  }

  Future<void> updateAll() async {
    for (var i = 0; i < state.messages.length; i++) {
      await update(i);
    }
  }

  Future<void> rename(String title) async {
    final id = state.conversationId;
    final t = title.trim();
    if (t.isEmpty) return;
    state = state.copyWith(title: t);
    if (id != null) await _repo.rename(id, t);
  }

  Future<void> deleteConversation() async {
    final id = state.conversationId;
    if (id != null) await _repo.delete(id);
    startNew();
  }

  Future<void> _record(
    AskMessage? question,
    AskTurn turn,
    DateTime now, {
    bool replaceLast = false,
  }) async {
    final reply = AskMessage(
      role: AskRole.reply,
      text: '',
      createdAt: now,
      answer: turn.answer,
    );
    var messages = [...state.messages];
    if (replaceLast && messages.isNotEmpty) messages.removeLast();
    var title = state.title;
    if (title == null && turn.context.intent != null && turn.answer.canUpdate) {
      title = conversationTitle(turn.context, CalendarDate.local(now));
    }
    var id = state.conversationId;
    final save = (await _settings).save;
    var savedQuestion = question;
    var savedReply = reply;
    if (save) {
      id ??= await _repo.start(title ?? question?.text ?? 'Conversation', now);
      if (state.title == null &&
          title != null &&
          state.conversationId != null) {
        await _repo.rename(id, title);
      }
      if (question != null) {
        savedQuestion = AskMessage(
          id: await _repo.add(id, question),
          role: question.role,
          text: question.text,
          createdAt: question.createdAt,
          understanding: question.understanding,
        );
      }
      savedReply = AskMessage(
        id: await _repo.add(id, reply),
        role: reply.role,
        text: reply.text,
        createdAt: reply.createdAt,
        answer: reply.answer,
      );
      await _repo.setContext(id, turn.context, now);
    }
    messages = [...messages, ?savedQuestion, savedReply];
    state = state.copyWith(
      conversationId: id,
      title: title,
      messages: messages,
      context: turn.context,
      lastAt: now,
    );
  }
}

final askControllerProvider = NotifierProvider<AskController, AskSession>(
  AskController.new,
);
