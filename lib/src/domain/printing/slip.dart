import 'dart:convert';
import 'dart:typed_data';

/// One line of a printed slip.
sealed class SlipLine {
  const SlipLine();
}

/// [text] on its own, centred; [bold] and [large] for headings.
class SlipCentre extends SlipLine {
  const SlipCentre(this.text, {this.bold = false, this.large = false});

  final String text;
  final bool bold;
  final bool large;
}

/// [left] and [right] at either edge, such as an item and its price.
class SlipPair extends SlipLine {
  const SlipPair(this.left, this.right, {this.bold = false});

  final String left;
  final String right;
  final bool bold;
}

/// A dashed rule across the paper.
class SlipRule extends SlipLine {
  const SlipRule();
}

/// What a counter printer prints: a receipt or the day's summary, line by
/// line, in the printer's own font.
class Slip {
  const Slip(this.lines);

  final List<SlipLine> lines;

  /// The characters across [mm] of paper in the printer's normal font.
  static int columnsFor(int mm) => mm >= 80 ? 48 : 32;

  /// The slip as plain lines [columns] wide, as it prints.
  List<String> render(int columns) {
    final out = <String>[];
    for (final line in lines) {
      switch (line) {
        case SlipCentre(:final text, :final large):
          final width = large ? columns ~/ 2 : columns;
          for (final part in _wrap(printable(text), width)) {
            final pad = (width - part.length) ~/ 2;
            out.add('${' ' * pad}$part');
          }
        case SlipPair(:final left, :final right):
          out.addAll(_pair(printable(left), printable(right), columns));
        case SlipRule():
          out.add('-' * columns);
      }
    }
    return out;
  }

  /// The slip as ESC/POS commands for a [mm] wide receipt printer: plain
  /// text in the printer's font, then a feed and a cut.
  Uint8List escPos(int mm) {
    final columns = columnsFor(mm);
    final bytes = BytesBuilder()
      ..add(const [_esc, 0x40]) // Reset.
      ..add(const [_esc, 0x74, 16]); // Code page: Windows Latin 1.
    void writeLine(String s) => bytes
      ..add(latin1.encode(s))
      ..addByte(0x0A);
    for (final line in lines) {
      switch (line) {
        case SlipCentre(:final text, :final bold, :final large):
          bytes
            ..add(const [_esc, 0x61, 1])
            ..add([_esc, 0x45, bold ? 1 : 0])
            ..add([_gs, 0x21, large ? 0x11 : 0x00]);
          final width = large ? columns ~/ 2 : columns;
          for (final part in _wrap(printable(text), width)) {
            writeLine(part);
          }
          bytes
            ..add(const [_gs, 0x21, 0x00])
            ..add(const [_esc, 0x45, 0])
            ..add(const [_esc, 0x61, 0]);
        case SlipPair(:final left, :final right, :final bold):
          bytes.add([_esc, 0x45, bold ? 1 : 0]);
          for (final part in _pair(
            printable(left),
            printable(right),
            columns,
          )) {
            writeLine(part);
          }
          bytes.add(const [_esc, 0x45, 0]);
        case SlipRule():
          writeLine('-' * columns);
      }
    }
    bytes
      ..add(const [_esc, 0x64, 4]) // Feed four lines.
      ..add(const [_gs, 0x56, 66, 0]); // Cut, where the printer can.
    return bytes.toBytes();
  }

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  /// [left] and [right] on one line when they fit, else [left] wrapped with
  /// [right] at the end of its last line.
  static List<String> _pair(String left, String right, int columns) {
    if (left.length + right.length + 1 <= columns) {
      return ['$left${' ' * (columns - left.length - right.length)}$right'];
    }
    final parts = _wrap(left, columns);
    final last = parts.removeLast();
    if (last.length + right.length + 1 <= columns) {
      return [
        ...parts,
        '$last${' ' * (columns - last.length - right.length)}$right',
      ];
    }
    return [...parts, last, '${' ' * (columns - right.length)}$right'];
  }

  static List<String> _wrap(String text, int width) {
    final words = text.split(' ').where((w) => w.isNotEmpty);
    final out = <String>[];
    var line = '';
    for (var word in words) {
      while (word.length > width) {
        if (line.isNotEmpty) {
          out.add(line);
          line = '';
        }
        out.add(word.substring(0, width));
        word = word.substring(width);
      }
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= width) {
        line = '$line $word';
      } else {
        out.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty || out.isEmpty) out.add(line);
    return out;
  }
}

/// [text] in characters every receipt printer has: `·` and `–` become
/// `-`, `×` becomes `x`, and anything else outside Latin 1 becomes `?`.
String printable(String text) {
  const swaps = {
    '·': '-',
    '–': '-',
    '—': '-',
    '×': 'x',
    '…': '...',
    '≈': '~',
    '→': '->',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    ' ': ' ',
  };
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final swap = swaps[char];
    if (swap != null) {
      buffer.write(swap);
    } else if (rune < 0x20) {
      buffer.write(' ');
    } else if (rune <= 0xFF) {
      buffer.write(char);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}
