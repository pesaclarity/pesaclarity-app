import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/reader/review_spike.dart';
import '../../backup/application/backup_providers.dart';
import '../../backup/data/key_value_store.dart';
import 'review_providers.dart';

/// Where the spikes already told about are kept, on this phone only.
final reviewSpikeStoreProvider = Provider<KeyValueStore>(
  (ref) => ref.watch(backupKeyValueStoreProvider),
);

const _toldKey = 'review_spike_told';

/// Per institution, the newest review item id of the last spike the person
/// was told about.
final reviewSpikeToldProvider =
    AsyncNotifierProvider<ReviewSpikeTold, Map<String, int>>(
      ReviewSpikeTold.new,
    );

class ReviewSpikeTold extends AsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() async {
    try {
      final raw = await ref.read(reviewSpikeStoreProvider).read(_toldKey);
      if (raw == null) return {};
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (value is int) key: value,
      };
    } on Object {
      return {};
    }
  }

  /// Marks [spike] told, so it shows no more.
  Future<void> told(ReviewSpike spike) async {
    final next = {...?state.value, spike.institutionId: spike.newestId};
    state = AsyncData(next);
    try {
      await ref
          .read(reviewSpikeStoreProvider)
          .write(_toldKey, jsonEncode(next));
    } on Object {
      // Kept for this run; told again after a restart at worst.
    }
  }
}

/// Spikes in messages to check not told about yet, biggest first. See
/// [reviewSpikes] for the rule.
final reviewSpikesProvider = Provider<List<ReviewSpike>>((ref) {
  final items = ref.watch(pendingReviewProvider).value;
  final told = ref.watch(reviewSpikeToldProvider).value;
  if (items == null || told == null) return const [];
  return reviewSpikes(
    [
      for (final i in items)
        (id: i.id, institutionId: i.institutionId, receivedAt: i.receivedAt),
    ],
    now: ref.watch(clockProvider)(),
    toldUpTo: told,
  );
});
