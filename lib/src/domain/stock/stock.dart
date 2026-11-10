import '../enums.dart';

/// Quantities are kept in thousandths of a unit, so 0.5 kg is 500.
const milli = 1000;

/// One thing a business sells.
class Item {
  const Item({
    required this.id,
    required this.kind,
    required this.name,
    this.unit,
    this.priceMinor,
    this.stockMilli = 0,
    this.averageCostMinor = 0,
    this.warnBelowMilli,
    this.grouping,
  });

  final int id;
  final ItemKind kind;
  final String name;

  /// Such as kg or bunch; null sells each.
  final String? unit;

  /// Per unit; null when the price varies.
  final int? priceMinor;
  final int stockMilli;

  /// What one unit costs, on average.
  final int averageCostMinor;
  final int? warnBelowMilli;
  final String? grouping;

  bool get isProduct => kind == ItemKind.product;

  /// This item with [stockMilli] on hand.
  Item withStock(int stockMilli) => Item(
    id: id,
    kind: kind,
    name: name,
    unit: unit,
    priceMinor: priceMinor,
    stockMilli: stockMilli,
    averageCostMinor: averageCostMinor,
    warnBelowMilli: warnBelowMilli,
    grouping: grouping,
  );

  /// Below "warn me below".
  bool get isLow =>
      isProduct && warnBelowMilli != null && stockMilli < warnBelowMilli!;

  /// What the stock on hand cost.
  int get valueMinor =>
      isProduct && stockMilli > 0 ? costOf(stockMilli, averageCostMinor) : 0;

  /// Price less average cost, per unit.
  int? get profitPerUnitMinor => priceMinor == null
      ? null
      : priceMinor! - (isProduct ? averageCostMinor : 0);
}

/// What [quantityMilli] costs at [perUnitMinor] a unit, to the nearest
/// cent.
int costOf(int quantityMilli, int perUnitMinor) =>
    (quantityMilli * perUnitMinor / milli).round();

/// The average cost a unit after buying [quantityMilli] for [paidMinor]
/// with [stockMilli] already there at [averageMinor] each. Stock below
/// zero counts as none.
int newAverageCost({
  required int stockMilli,
  required int averageMinor,
  required int quantityMilli,
  required int paidMinor,
}) {
  final before = stockMilli > 0 ? stockMilli : 0;
  final total = before + quantityMilli;
  if (total <= 0) return averageMinor;
  return ((before * averageMinor / milli + paidMinor) * milli / total).round();
}

/// A quantity as people say it: `6`, `0.5`, `2.25`.
String quantityText(int quantityMilli) {
  final whole = quantityMilli ~/ milli;
  final part = (quantityMilli % milli).abs();
  if (part == 0) return '$whole';
  final digits = part
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final sign = quantityMilli < 0 && whole == 0 ? '-' : '';
  return '$sign$whole.$digits';
}

/// Units that read the same for one or many.
const _sameForMany = {'kg', 'g', 'l', 'ml', 'litres', 'kgs'};

/// [unit] for [quantityMilli] of it: `bunches`, `kg`.
String unitFor(String unit, int quantityMilli) {
  final u = unit.trim();
  if (quantityMilli == milli || _sameForMany.contains(u.toLowerCase())) {
    return u;
  }
  if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(u)) return '${u}es';
  return '${u}s';
}

/// A stock level as people say it: `38 bunches`, `6 kg`, `22 left`.
String stockText(Item item) {
  final q = quantityText(item.stockMilli);
  final unit = item.unit;
  return unit == null ? '$q left' : '$q ${unitFor(unit, item.stockMilli)}';
}

/// A price as people say it: `20 / bunch`, `30 each`, or `Price varies`.
String priceText(Item item, String Function(int minor) plain) {
  final price = item.priceMinor;
  if (price == null) return 'Price varies';
  final unit = item.unit;
  return unit == null ? '${plain(price)} each' : '${plain(price)} / $unit';
}

/// Days the stock lasts at the pace of [soldMilliPerDay]; null without
/// recent sales.
int? daysLeft(Item item, {required double soldMilliPerDay}) {
  if (!item.isProduct || soldMilliPerDay <= 0) return null;
  if (item.stockMilli <= 0) return 0;
  return (item.stockMilli / soldMilliPerDay).floor();
}

/// The quantity in [text] in thousandths: `0.5` is 500, `2` is 2000. Null
/// when it is not a quantity, or has more than three decimal places.
int? quantityFrom(String text) {
  final clean = text.trim().replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(clean);
  if (match == null) return null;
  final whole = int.parse(match[1]!);
  final part = (match[2] ?? '').padRight(3, '0');
  return whole * milli + (part.isEmpty ? 0 : int.parse(part));
}
