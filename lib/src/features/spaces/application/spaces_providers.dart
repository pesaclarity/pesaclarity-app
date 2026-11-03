import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/spaces/space.dart';
import '../../income/application/income_providers.dart';

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
    // A business plans week by week from its first day.
    if (kind == SpaceKind.business) {
      await ref.read(incomeSourcesProvider.notifier).choose({
        IncomeSource.business,
      });
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
