/// A sudden jump in one institution's messages to check, which almost
/// always means it changed the wording of its messages.
///
/// The rule, kept simple so it can be explained in one sentence: an
/// institution has a spike when at least [reviewSpikeMinNew] of its
/// messages to check arrived in the last [reviewSpikeWindow], and that is at
/// least [reviewSpikeTimesUsual] times its usual count for the same length
/// of time, the usual being its daily average over the
/// [reviewSpikeBaseline] before the window (at least one a day, so a quiet
/// institution still needs [reviewSpikeMinNew] in a day).
///
/// Only messages still waiting are counted; once checked, an item's text
/// is deleted and it no longer adds to either count. Everything here runs
/// on the phone; nothing is sent anywhere.
library;

/// The window new messages are counted in.
const reviewSpikeWindow = Duration(hours: 24);

/// How far back, before the window, the usual count is taken from.
const reviewSpikeBaseline = Duration(days: 14);

/// The fewest new messages from one institution that count as a spike.
/// Fewer is ordinary: a new kind of message now and then.
const reviewSpikeMinNew = 5;

/// How many times its usual count the window must hold.
const reviewSpikeTimesUsual = 3;

/// One message to check, as far as spotting a spike needs.
typedef ReviewSpikeItem = ({int id, String institutionId, DateTime receivedAt});

/// One institution's spike: how many of its messages wait to be checked
/// and the newest of those that make up the spike, to tell it once.
class ReviewSpike {
  const ReviewSpike({
    required this.institutionId,
    required this.waiting,
    required this.newestId,
  });

  final String institutionId;

  /// Every message from the institution waiting to be checked.
  final int waiting;

  /// The id of the newest item in the spike; a spike whose newest item is
  /// at or below the one last told about is the same spike.
  final int newestId;

  @override
  bool operator ==(Object other) =>
      other is ReviewSpike &&
      other.institutionId == institutionId &&
      other.waiting == waiting &&
      other.newestId == newestId;

  @override
  int get hashCode => Object.hash(institutionId, waiting, newestId);

  @override
  String toString() => 'ReviewSpike($institutionId, $waiting, #$newestId)';
}

/// The spikes among [items] at [now], biggest first. [toldUpTo] holds, per
/// institution, the newest item id already told about: only items after it
/// count as new, so each spike is told once.
List<ReviewSpike> reviewSpikes(
  List<ReviewSpikeItem> items, {
  required DateTime now,
  Map<String, int> toldUpTo = const {},
}) {
  final windowStart = now.subtract(reviewSpikeWindow);
  final baselineStart = windowStart.subtract(reviewSpikeBaseline);
  final byInstitution = <String, List<ReviewSpikeItem>>{};
  for (final item in items) {
    byInstitution.putIfAbsent(item.institutionId, () => []).add(item);
  }
  final spikes = <ReviewSpike>[];
  for (final MapEntry(key: id, value: list) in byInstitution.entries) {
    final told = toldUpTo[id] ?? -1;
    final recent = [
      for (final i in list)
        if (i.id > told && !i.receivedAt.isBefore(windowStart)) i,
    ];
    if (recent.length < reviewSpikeMinNew) continue;
    final before = list
        .where(
          (i) =>
              i.receivedAt.isBefore(windowStart) &&
              !i.receivedAt.isBefore(baselineStart),
        )
        .length;
    final perWindow =
        before * reviewSpikeWindow.inMinutes / reviewSpikeBaseline.inMinutes;
    final usual = perWindow < 1 ? 1.0 : perWindow;
    if (recent.length < reviewSpikeTimesUsual * usual) continue;
    spikes.add(
      ReviewSpike(
        institutionId: id,
        waiting: list.length,
        newestId: recent.map((i) => i.id).reduce((a, b) => a > b ? a : b),
      ),
    );
  }
  spikes.sort((a, b) => b.waiting.compareTo(a.waiting));
  return spikes;
}
