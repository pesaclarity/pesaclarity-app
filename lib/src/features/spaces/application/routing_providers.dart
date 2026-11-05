import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/connection.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/institutions_repository.dart';
import '../../../data/repositories/space_move_repository.dart';
import '../../../domain/spaces/line_routing.dart';
import '../../../domain/spaces/space.dart';
import 'spaces_providers.dart';

/// How far back the business asks about payments on a shared line.
const sharedLineLookback = Duration(days: 30);

/// Most "kept in Personal" answers remembered, newest kept.
const keptPersonalLimit = 2000;

/// The line rules, in Personal's settings.
class RoutingRulesController extends AsyncNotifier<RoutingRules> {
  static const settingsKey = 'routing.rules';

  AppSettingsRepository get _settings =>
      ref.read(mainSettingsRepositoryProvider);

  @override
  Future<RoutingRules> build() async =>
      RoutingRules.fromJson(await _settings.readJson(settingsKey));

  Future<RoutingRules> _current() async => state.value ?? await future;

  Future<void> _save(RoutingRules next) async {
    await _settings.writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }

  /// Sets where [institutionId] is read, for the business [businessId].
  ///
  /// [LineChoice.both] keeps the line in Personal only, so each message is
  /// read once, and the business asks about its payments.
  Future<void> setLine(
    String institutionId,
    LineChoice choice, {
    required String businessId,
    required InstitutionsRepository business,
    required InstitutionsRepository personal,
  }) async {
    final current = await _current();
    await business.setSelected(
      institutionId,
      selected: choice == LineChoice.thisBusiness,
    );
    await personal.setSelected(
      institutionId,
      selected: choice != LineChoice.thisBusiness,
    );
    await _save(
      current.withLine(
        institutionId,
        choice == LineChoice.both ? businessId : null,
      ),
    );
  }

  /// Remembers that money from [key] goes to [spaceId].
  Future<void> rememberPerson(String key, String spaceId) async =>
      _save((await _current()).withPerson(key, spaceId));
}

final routingRulesProvider =
    AsyncNotifierProvider<RoutingRulesController, RoutingRules>(
      RoutingRulesController.new,
    );

/// A payment on a shared line, waiting for "Was this for the business?".
class SharedLineQuestion {
  const SharedLineQuestion({
    required this.transactionId,
    required this.institutionId,
    required this.amountMinor,
    required this.currency,
    required this.isInflow,
    required this.at,
    this.name,
    this.personKey,
  });

  /// The transaction's id in Personal.
  final int transactionId;
  final String institutionId;
  final int amountMinor;
  final String currency;
  final bool isInflow;
  final DateTime at;

  /// The other party's name as the message gave it.
  final String? name;
  final String? personKey;
}

/// Sorts money on shared lines between Personal and a business: it lists
/// what to ask about, applies what the owner taught it, and moves answered
/// payments.
class SharedLineRouter {
  SharedLineRouter({
    required AppDatabase personal,
    required SpaceMoveRepository moveFromPersonal,
    required this.rules,
    required this.remember,
    required this.now,
  }) : _personal = personal,
       _move = moveFromPersonal,
       _kept = DriftAppSettingsRepository(personal);

  static const keptKey = 'routing.keptPersonal';

  final AppDatabase _personal;
  final SpaceMoveRepository _move;

  /// Reads the current rules.
  final Future<RoutingRules> Function() rules;

  /// Saves that money from a person goes to a space.
  final Future<void> Function(String key, String spaceId) remember;
  final DateTime Function() now;
  final AppSettingsRepository _kept;

  Future<List<int>> _keptIds() async {
    final raw = (await _kept.readJson(keptKey))?['ids'];
    return [
      if (raw is List)
        for (final id in raw)
          if (id is int) id,
    ];
  }

  Future<void> _keep(int transactionId) async {
    final ids = [...await _keptIds(), transactionId];
    final trimmed = ids.length > keptPersonalLimit
        ? ids.sublist(ids.length - keptPersonalLimit)
        : ids;
    await _kept.writeJson(keptKey, {'ids': trimmed});
  }

  /// Recent payments in Personal on any line shared with a business, newest
  /// first, that are not own transfers and not yet kept in Personal.
  Future<List<(SharedLineQuestion, String)>> _recent(RoutingRules rules) async {
    if (rules.sharedLines.isEmpty) return const [];
    final t = _personal.transactions;
    final a = _personal.accounts;
    final since = now().subtract(sharedLineLookback);
    final rows =
        await (_personal.select(t).join([
                innerJoin(a, a.id.equalsExp(t.accountId)),
              ])
              ..where(
                a.institutionId.isIn(rules.sharedLines.keys) &
                    t.occurredAt.isBiggerOrEqualValue(since) &
                    t.transferPairId.isNull(),
              )
              ..orderBy([OrderingTerm.desc(t.occurredAt)]))
            .get();
    final kept = (await _keptIds()).toSet();
    return [
      for (final row in rows)
        if (row.readTable(t) case final tx when !kept.contains(tx.id))
          (
            SharedLineQuestion(
              transactionId: tx.id,
              institutionId: row.readTable(a).institutionId!,
              amountMinor: tx.amountMinor,
              currency: tx.currency,
              isInflow: tx.direction.name == 'inflow',
              at: tx.occurredAt,
              name: tx.counterpartyName,
              personKey: personKey(
                kind: tx.counterpartyKind,
                value: tx.counterpartyValue,
                name: tx.counterpartyName,
              ),
            ),
            rules.sharedLines[row.readTable(a).institutionId!]!,
          ),
    ];
  }

  /// Moves or keeps every recent payment whose person the owner already
  /// taught the app about. Returns how many it sorted.
  Future<int> applyRules() async {
    final current = await rules();
    var sorted = 0;
    for (final (q, business) in await _recent(current)) {
      final target = q.personKey == null ? null : current.people[q.personKey];
      if (target == null) continue;
      if (target == personalSpaceId) {
        await _keep(q.transactionId);
      } else if (target == business) {
        await _move.move(q.transactionId, business);
      } else {
        continue;
      }
      sorted++;
    }
    return sorted;
  }

  /// What [businessId] still has to ask about, after applying the rules.
  Future<List<SharedLineQuestion>> pending(String businessId) async {
    await applyRules();
    final current = await rules();
    return [
      for (final (q, business) in await _recent(current))
        if (business == businessId &&
            (q.personKey == null || !current.people.containsKey(q.personKey)))
          q,
    ];
  }

  /// Answers [question]: moves it to [businessId] or keeps it in Personal,
  /// and with [always] remembers the choice for its person.
  Future<void> answer(
    SharedLineQuestion question, {
    required String businessId,
    required bool forBusiness,
    required bool always,
  }) async {
    if (forBusiness) {
      await _move.move(question.transactionId, businessId);
    } else {
      await _keep(question.transactionId);
    }
    final key = question.personKey;
    if (always && key != null) {
      await remember(key, forBusiness ? businessId : personalSpaceId);
    }
  }
}

/// The router, moving out of Personal into whichever business is asked.
final sharedLineRouterProvider = Provider<SharedLineRouter>((ref) {
  final personal = ref.watch(personalDatabaseProvider);
  final active = ref.watch(activeSpaceIdProvider);
  final mover = DriftSpaceMoveRepository(personal, (spaceId) async {
    if (spaceId == active) return (ref.read(appDatabaseProvider), false);
    final db = openEncryptedDatabase(
      ref.read(databaseKeyStoreProvider),
      beforeOpen: ref.read(databaseFileLockProvider).waitUntilFree,
      spaceId: spaceId,
    );
    return (db, true);
  });
  return SharedLineRouter(
    personal: personal,
    moveFromPersonal: mover,
    rules: () => ref.read(routingRulesProvider.future),
    remember: (key, spaceId) =>
        ref.read(routingRulesProvider.notifier).rememberPerson(key, spaceId),
    now: ref.watch(clockProvider),
  );
});

/// Payments the open business has to ask about; empty in Personal and in
/// spaces that are not a business.
final sharedLineQuestionsProvider = FutureProvider<List<SharedLineQuestion>>((
  ref,
) async {
  final space = ref.watch(activeSpaceProvider);
  if (space.kind != SpaceKind.business) return const [];
  ref.watch(routingRulesProvider);
  // Questions are a nudge: if Personal cannot be read, Home goes on without
  // them.
  try {
    return await ref.watch(sharedLineRouterProvider).pending(space.id);
  } on Object catch (error) {
    if (kDebugMode) debugPrint('Shared account questions failed: $error');
    return const [];
  }
});
