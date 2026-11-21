/// Spacing and corners used on every screen, so screens line up.
abstract final class Layout {
  /// Space at the left and right of a screen and a sheet.
  static const gutter = 20.0;

  /// Space between two cards, and between two tiles side by side.
  static const cardGap = 12.0;

  /// Space inside a card around its content.
  static const cardPadding = 16.0;

  /// Cards start at a size that reads well and grow with their content,
  /// never shrinking below it (8 dp grid).
  static const heroMinHeight = 128.0;
  static const heroPadding = 20.0;
  static const tileMinHeight = 96.0;
  static const rowMinHeight = 64.0;

  /// Space above and below a section's header, on every screen.
  static const sectionTop = 24.0;
  static const sectionBottom = 8.0;

  /// The smallest tap area, even when the part drawn is smaller.
  static const minTouch = 48.0;

  /// Space below a tab's title row.
  static const titleGap = 16.0;

  /// Space at the end of a tab's list, clear of the round button.
  static const tabBottom = 96.0;

  /// Space at the end of a pushed screen's list.
  static const screenBottom = 24.0;

  /// Corner of a box inside a screen: a note, a selectable tile, a badge
  /// panel. The same as a card's (`BrandTokens.cardRadius`): a card is
  /// rounded at 20 and a control is a pill, and nothing else.
  static const panelRadius = 20.0;

  /// Corner of a small tag beside a name: a pill, as every control is.
  static const tagRadius = 999.0;
}
