import '../stock/stock.dart';

/// A tab still open: rounds added for a table or a person, paid together.
class OpenTab {
  const OpenTab({
    required this.id,
    required this.name,
    required this.openedAt,
    required this.quantityMilli,
    required this.totalMinor,
  });

  final int id;

  /// Such as Table 4 or a name.
  final String name;
  final DateTime openedAt;

  /// Everything on it, in thousandths, whichever way each was sold.
  final int quantityMilli;
  final int totalMinor;

  /// How many things are on it, as people count them: `13`.
  int get itemCount => (quantityMilli / milli).round();
}

/// One line of a round on a tab.
class TabLine {
  const TabLine({
    required this.id,
    required this.at,
    required this.name,
    required this.quantityMilli,
    required this.totalMinor,
    this.itemId,
    this.measureId,
  });

  final int id;

  /// When its round was added.
  final DateTime at;
  final int? itemId;
  final int? measureId;
  final String name;
  final int quantityMilli;
  final int totalMinor;
}

/// `13 items`, `1 item`.
String itemsText(int count) => count == 1 ? '1 item' : '$count items';
