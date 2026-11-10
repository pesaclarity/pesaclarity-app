/// Spacing and corners used on every screen, so screens line up.
abstract final class Layout {
  /// Space at the left and right of a screen and a sheet.
  static const gutter = 20.0;

  /// Space between two cards, and between two tiles side by side.
  static const cardGap = 12.0;

  /// Space inside a card around its content.
  static const cardPadding = 16.0;

  /// Space below a tab's title row.
  static const titleGap = 16.0;

  /// Space at the end of a tab's list, clear of the round button.
  static const tabBottom = 96.0;

  /// Space at the end of a pushed screen's list.
  static const screenBottom = 24.0;

  /// Corner of a box inside a screen: a note, a selectable tile, a badge
  /// panel. Cards use `BrandTokens.cardRadius`.
  static const panelRadius = 16.0;

  /// Corner of a small tag beside a name.
  static const tagRadius = 8.0;
}
