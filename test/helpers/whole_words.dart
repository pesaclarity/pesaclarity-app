import 'package:flutter/rendering.dart';

/// A word: a run of letters and digits.
final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// The words [text] draws across two lines, such as "Achie" at the end of
/// one line and "ng" at the start of the next. A word the line ends in
/// "..." before is not broken: it is shortened, which other checks report.
List<String> brokenWords(RenderParagraph text) {
  final plain = text.text.toPlainText();
  return [
    for (final match in _word.allMatches(plain))
      if (match.end - match.start > 1 &&
          {
                for (final box in text.getBoxesForSelection(
                  TextSelection(
                    baseOffset: match.start,
                    extentOffset: match.end,
                  ),
                ))
                  if (box.right - box.left > 0.5) box.top.round(),
              }.length >
              1)
        match[0]!,
  ];
}
