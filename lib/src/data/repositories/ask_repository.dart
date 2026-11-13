import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ask/answer.dart';
import '../../domain/ask/context.dart';
import '../../domain/ask/matcher.dart';
import '../../domain/ask/understanding.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// A saved conversation, newest change last.
class AskConversation {
  const AskConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.context = AskContext.empty,
    this.lastReply,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AskContext context;

  /// The latest reply's answer, for the list's second line.
  final AskAnswer? lastReply;
}

enum AskRole { person, reply }

/// One saved question or reply.
class AskMessage {
  const AskMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.id,
    this.understanding,
    this.answer,
  });

  final int? id;
  final AskRole role;
  final String text;
  final DateTime createdAt;
  final Understanding? understanding;
  final AskAnswer? answer;

  AskMessage withAnswer(AskAnswer answer) => AskMessage(
    id: id,
    role: role,
    text: text,
    createdAt: createdAt,
    understanding: understanding,
    answer: answer,
  );
}

/// Ask's conversations and shortcuts, in the open space's own database.
abstract interface class AskRepository {
  Stream<List<AskConversation>> watchConversations();

  Future<AskConversation?> conversation(int id);

  Future<List<AskMessage>> messages(int conversationId);

  Future<int> start(String title, DateTime at);

  /// Adds [message] and returns its id.
  Future<int> add(int conversationId, AskMessage message);

  /// Puts [answer] on reply [messageId], as after Update.
  Future<void> replaceAnswer(int messageId, AskAnswer answer);

  Future<void> setContext(int conversationId, AskContext context, DateTime at);

  Future<void> rename(int conversationId, String title);

  Future<void> delete(int conversationId);

  Future<void> deleteAll();

  /// Removes conversations last changed before [before].
  Future<int> purgeBefore(DateTime before);

  Future<List<AskShortcut>> shortcuts();

  Future<void> learn(String word, AskEntity entity, DateTime at);
}

class DriftAskRepository implements AskRepository {
  DriftAskRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<AskConversation>> watchConversations() {
    final c = _db.askConversations;
    return (_db.select(
      c,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch().asyncMap(
      (rows) async => [
        for (final row in rows) _conversation(row, await _lastAnswer(row.id)),
      ],
    );
  }

  Future<AskAnswer?> _lastAnswer(int conversationId) async {
    final m = _db.askMessages;
    final row =
        await (_db.select(m)
              ..where(
                (t) =>
                    t.conversationId.equals(conversationId) &
                    t.answerJson.isNotNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull();
    return _answer(row?.answerJson);
  }

  @override
  Future<AskConversation?> conversation(int id) async {
    final row = await (_db.select(
      _db.askConversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _conversation(row, await _lastAnswer(id));
  }

  AskConversation _conversation(AskConversationRecord row, AskAnswer? last) =>
      AskConversation(
        id: row.id,
        title: row.title,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        context:
            _json(row.contextJson, AskContext.fromJson) ?? AskContext.empty,
        lastReply: last,
      );

  @override
  Future<List<AskMessage>> messages(int conversationId) async {
    final m = _db.askMessages;
    final rows =
        await (_db.select(m)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return [
      for (final r in rows)
        AskMessage(
          id: r.id,
          role: AskRole.values.asNameMap()[r.role] ?? AskRole.reply,
          text: r.body,
          createdAt: r.createdAt,
          understanding: _json(r.understandingJson, Understanding.fromJson),
          answer: _answer(r.answerJson),
        ),
    ];
  }

  @override
  Future<int> start(String title, DateTime at) => _db
      .into(_db.askConversations)
      .insert(
        AskConversationsCompanion.insert(
          title: _fit(title),
          createdAt: at,
          updatedAt: at,
        ),
      );

  @override
  Future<int> add(int conversationId, AskMessage message) =>
      _db.transaction(() async {
        final id = await _db
            .into(_db.askMessages)
            .insert(
              AskMessagesCompanion.insert(
                conversationId: conversationId,
                role: message.role.name,
                body: message.text,
                understandingJson: Value(
                  message.understanding == null
                      ? null
                      : jsonEncode(message.understanding!.toJson()),
                ),
                answerJson: Value(
                  message.answer == null
                      ? null
                      : jsonEncode(message.answer!.toJson()),
                ),
                createdAt: message.createdAt,
              ),
            );
        await (_db.update(
          _db.askConversations,
        )..where((t) => t.id.equals(conversationId))).write(
          AskConversationsCompanion(updatedAt: Value(message.createdAt)),
        );
        return id;
      });

  @override
  Future<void> replaceAnswer(int messageId, AskAnswer answer) =>
      (_db.update(_db.askMessages)..where((t) => t.id.equals(messageId))).write(
        AskMessagesCompanion(answerJson: Value(jsonEncode(answer.toJson()))),
      );

  @override
  Future<void> setContext(
    int conversationId,
    AskContext context,
    DateTime at,
  ) =>
      (_db.update(
        _db.askConversations,
      )..where((t) => t.id.equals(conversationId))).write(
        AskConversationsCompanion(
          contextJson: Value(jsonEncode(context.toJson())),
          updatedAt: Value(at),
        ),
      );

  @override
  Future<void> rename(int conversationId, String title) =>
      (_db.update(_db.askConversations)
            ..where((t) => t.id.equals(conversationId)))
          .write(AskConversationsCompanion(title: Value(_fit(title))));

  @override
  Future<void> delete(int conversationId) => (_db.delete(
    _db.askConversations,
  )..where((t) => t.id.equals(conversationId))).go();

  @override
  Future<void> deleteAll() => _db.transaction(() async {
    await _db.delete(_db.askMessages).go();
    await _db.delete(_db.askConversations).go();
    await _db.delete(_db.askShortcuts).go();
  });

  @override
  Future<int> purgeBefore(DateTime before) => (_db.delete(
    _db.askConversations,
  )..where((t) => t.updatedAt.isSmallerThanValue(before))).go();

  @override
  Future<List<AskShortcut>> shortcuts() async => [
    for (final r in await _db.select(_db.askShortcuts).get())
      if (SlotKind.values.asNameMap()[r.entityKind] case final kind?)
        AskShortcut(r.word, kind, r.entityKey),
  ];

  @override
  Future<void> learn(String word, AskEntity entity, DateTime at) => _db
      .into(_db.askShortcuts)
      .insert(
        AskShortcutsCompanion.insert(
          word: _fit(normaliseName(word), 60),
          entityKind: entity.kind.name,
          entityKey: entity.key,
          createdAt: at,
        ),
        onConflict: DoUpdate(
          (_) => AskShortcutsCompanion(
            entityKind: Value(entity.kind.name),
            entityKey: Value(entity.key),
            createdAt: Value(at),
          ),
          target: [_db.askShortcuts.word],
        ),
      );

  static String _fit(String text, [int max = 80]) {
    final t = text.trim().isEmpty ? 'Conversation' : text.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  static T? _json<T>(String? text, T Function(Map<String, Object?>) read) {
    if (text == null) return null;
    try {
      return read((jsonDecode(text) as Map).cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  static AskAnswer? _answer(String? text) => _json(text, AskAnswer.fromJson);
}

/// Ask's store in the open space.
final askRepositoryProvider = Provider<AskRepository>(
  (ref) => DriftAskRepository(ref.watch(appDatabaseProvider)),
);
