import 'package:ujumbe/ujumbe.dart' show PageWord, StatementPage;

/// Groups a page's characters into words with their boxes.
///
/// [boxes] are PDF coordinates (origin bottom-left, y up), one per
/// character of [text]; the result has the origin top-left, y down, as
/// ujumbe expects. PDFium's boxes hug each character's ink, so narrow
/// characters leave gaps as wide as a space: words end where PDFium put
/// whitespace, where the text moves to another line, or at a jump wider
/// than the word is tall, as between two columns printed with no space.
StatementPage pageFromCharacters(
  String text,
  List<(double left, double top, double right, double bottom)> boxes, {
  required double pageHeight,
}) {
  final words = <PageWord>[];
  final buffer = StringBuffer();
  double left = 0, top = 0, right = 0, bottom = 0;

  void flush() {
    if (buffer.isEmpty) return;
    words.add(
      PageWord(
        buffer.toString(),
        left,
        pageHeight - top,
        right,
        pageHeight - bottom,
      ),
    );
    buffer.clear();
  }

  final count = text.length < boxes.length ? text.length : boxes.length;
  for (var i = 0; i < count; i++) {
    final char = text[i];
    final (l, t, r, b) = boxes[i];
    if (char.trim().isEmpty || r < l || t < b || (r == l && t == b)) {
      flush();
      continue;
    }
    if (buffer.isNotEmpty) {
      final overlapsLine = t > bottom && b < top;
      final height = (top - bottom) > (t - b) ? top - bottom : t - b;
      final jump = l - right > height || l < left;
      if (!overlapsLine || jump) flush();
    }
    if (buffer.isEmpty) {
      (left, top, right, bottom) = (l, t, r, b);
    } else {
      left = l < left ? l : left;
      top = t > top ? t : top;
      right = r > right ? r : right;
      bottom = b < bottom ? b : bottom;
    }
    buffer.write(char);
  }
  flush();
  return StatementPage(words);
}
