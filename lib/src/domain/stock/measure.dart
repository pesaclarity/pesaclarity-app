import 'stock.dart';

/// Another way an item is sold or bought besides the unit it is counted
/// in: a measure smaller than it, such as a tot of a bottle, or a pack of
/// several, such as a crate of bottles.
class Measure {
  const Measure({
    required this.id,
    required this.itemId,
    required this.name,
    required this.units,
    required this.bases,
    this.priceMinor,
  }) : assert(units > 0 && bases > 0);

  final int id;
  final int itemId;

  /// As the owner wrote it, such as `Tot, 25 ml` or `Crate`.
  final String name;

  /// [units] of this make [bases] of the item's own unit: 30 tots make
  /// 1 bottle, 1 crate makes 24 bottles.
  final int units;
  final int bases;

  /// What one sells for; null when it is only bought this way.
  final int? priceMinor;

  bool get sells => priceMinor != null;

  /// Holds more than one of the item's unit, such as a crate.
  bool get isPack => bases > units;

  /// `tot` from `Tot, 25 ml`.
  String get word => name.split(',').first.trim().toLowerCase();

  /// How much of the item's unit one of this is, for ordering.
  double get size => bases / units;

  /// Thousandths of the item's unit in [quantityMilli] of this, rounded.
  int baseMilli(int quantityMilli) => (quantityMilli * bases / units).round();

  /// Takes [quantityMilli] of this from stock exactly: what to take, in
  /// thousandths of the item's unit, and the part of a thousandth left
  /// over for next time, which [carry] brought in. Thirty tots always take
  /// one whole bottle.
  ({int takeMilli, int carry}) take(int quantityMilli, {int carry = 0}) {
    final total = carry + quantityMilli * bases;
    final left = total % units;
    return (takeMilli: (total - left) ~/ units, carry: left);
  }
}

/// [stockMilli] of an item counted in [unit], said with its [measures]:
/// `4 crates and 6 left`, `2 crates left`, `5 bottles and 12 tots`.
/// Null when no measure changes how it reads.
String? stockInMeasures(
  int stockMilli, {
  required String? unit,
  required List<Measure> measures,
}) {
  if (stockMilli < 0) return null;
  final packs = [
    for (final m in measures)
      if (m.isPack) m,
  ]..sort((a, b) => b.size.compareTo(a.size));
  for (final pack in packs) {
    if (stockMilli < pack.baseMilli(milli)) continue;
    return '${inPacks(stockMilli, pack)} left';
  }
  final parts = [
    for (final m in measures)
      if (!m.isPack) m,
  ]..sort((a, b) => a.size.compareTo(b.size));
  if (parts.isEmpty || unit == null) return null;
  final finest = parts.first;
  var whole = stockMilli ~/ milli;
  var pieces = ((stockMilli % milli) * finest.units / (milli * finest.bases))
      .round();
  final perUnit = finest.units ~/ finest.bases;
  if (perUnit > 0 && pieces >= perUnit) {
    whole += 1;
    pieces -= perUnit;
  }
  final wholeText = '$whole ${unitFor(unit, whole * milli).toLowerCase()}';
  if (pieces == 0) return wholeText;
  final piecesText = '$pieces ${plural(finest.word, pieces)}';
  return whole == 0 ? piecesText : '$wholeText and $piecesText';
}

/// [stockMilli] in whole [pack]s and what is over: `4 crates and 6`, or
/// with [unit] `4 crates and 6 bottles`; `2 crates` when none is over.
String inPacks(int stockMilli, Measure pack, {String? unit}) {
  final per = pack.baseMilli(milli);
  final count = stockMilli ~/ per;
  final rest = stockMilli - count * per;
  final packs = '$count ${plural(pack.word, count)}';
  if (rest == 0) return packs;
  final over = unit == null
      ? quantityText(rest)
      : '${quantityText(rest)} ${unitFor(unit, rest).toLowerCase()}';
  return '$packs and $over';
}

/// [word] for [count] of it: `crates`, `tots`, `boxes`.
String plural(String word, int count) {
  if (count == 1) return word;
  if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(word)) return '${word}es';
  return '${word}s';
}
