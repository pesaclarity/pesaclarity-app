import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_summary.dart';
import '../../../domain/time/calendar.dart';
import '../../income/application/income_providers.dart';
import '../../payees/application/payee_providers.dart';

/// Every space on this phone, Personal first, kept in Personal's database.
class SpacesController extends AsyncNotifier<List<Space>> {
  static const settingsKey = 'spaces.list';

  @override
  Future<List<Space>> build() async => spacesFromJson(
    await ref.watch(mainSettingsRepositoryProvider).readJson(settingsKey),
  );

  /// Adds a space and opens it. Returns its id.
  Future<String> add(String name, SpaceKind kind) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'is empty');
    final current = await future;
    final id = _newId(current);
    final next = [...current, Space(id: id, name: clean, kind: kind)];
    await _save(next);
    await ref.read(activeSpaceIdProvider.notifier).switchTo(id);
    await ref.read(appDatabaseProvider).becomeSpace(kind);
    // How money comes in, so a business plans week by week and a farm by
    // how long the money lasts, from the first day.
    final sources = switch (kind) {
      SpaceKind.business => {IncomeSource.business},
      SpaceKind.farm => {IncomeSource.seasonal},
      _ => null,
    };
    if (sources != null) {
      await ref.read(incomeSourcesProvider.notifier).choose(sources);
    }
    return id;
  }

  Future<void> rename(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final current = await future;
    await _save([
      for (final s in current) s.id == id ? s.copyWith(name: clean) : s,
    ]);
  }

  /// Makes [id] a [kind] of space. Its records stay; its categories follow
  /// the new kind. [db] is that space's database.
  Future<void> changeKind(String id, SpaceKind kind, AppDatabase db) async {
    if (id == personalSpaceId) return;
    final current = await future;
    await db.becomeSpace(kind);
    await _save([
      for (final s in current) s.id == id ? s.copyWith(kind: kind) : s,
    ]);
  }

  /// Takes [id] off the list. Its files are handled by the caller.
  Future<void> remove(String id) async {
    if (id == personalSpaceId) return;
    await _save([
      for (final s in await future)
        if (s.id != id) s,
    ]);
  }

  /// Puts [space] back on the list, as it was.
  Future<void> putBack(Space space) async {
    final current = await future;
    if (current.any((s) => s.id == space.id)) return;
    await _save([...current, space]);
  }

  Future<void> _save(List<Space> spaces) async {
    await ref
        .read(mainSettingsRepositoryProvider)
        .writeJson(settingsKey, spacesToJson(spaces));
    state = AsyncData(spaces);
  }

  static String _newId(List<Space> existing) {
    final random = Random.secure();
    while (true) {
      final id = List.generate(
        8,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
      ).join();
      if (existing.every((s) => s.id != id)) return id;
    }
  }
}

final spacesProvider = AsyncNotifierProvider<SpacesController, List<Space>>(
  SpacesController.new,
);

/// The open space, or Personal while the list loads.
final activeSpaceProvider = Provider<Space>((ref) {
  final id = ref.watch(activeSpaceIdProvider);
  final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
  return spaces.firstWhere((s) => s.id == id, orElse: () => Space.personal);
});

/// What Home shows first for a space that is not Personal; null for
/// Personal.
final spaceSummaryProvider = FutureProvider<SpaceSummary?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final space = ref.watch(activeSpaceProvider);
  if (space.kind == SpaceKind.personal) return null;
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  var from = today.addDays(-31 * farmSeasonMonths).startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: today.addDays(1).startInstant);
  final categories = await ref.watch(categoriesProvider.future);
  return SpaceSummary.of(
    space.kind,
    entries,
    today: today,
    categories: {
      for (final c in categories)
        c.id: (key: c.key, name: c.name, type: c.type),
    },
    balanceMinor: accounts.isEmpty
        ? 0
        : totalHeldAt(
            accounts,
            entries,
            at: today.addDays(1).startInstant,
            where: (_) => true,
          ),
  );
});
