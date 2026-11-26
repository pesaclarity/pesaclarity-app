import 'package:material_ui/material_ui.dart';

/// The height of an Ask app bar with [title] and the space's name under
/// it: the usual height, or more when [title] wraps to its second line in
/// [width] at large text, so both fit.
double askToolbarHeight(
  BuildContext context, {
  required String title,
  required TextStyle titleStyle,
  required String? spaceName,
  required TextStyle spaceStyle,
  required double width,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  double height(String text, TextStyle style, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: direction,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  final content =
      height(title, titleStyle, 2) +
      (spaceName == null ? 0 : height(spaceName, spaceStyle, 1));
  return content + 16 > kToolbarHeight ? content + 16 : kToolbarHeight;
}
