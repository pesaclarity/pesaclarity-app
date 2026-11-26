import 'dart:async';

import '../../../domain/ask/answer.dart';
import 'slm_answer.dart';
import 'slm_facts.dart';
import 'slm_generator.dart';

/// How long the money model may take before Ask answers without it.
const modelAnswerTimeout = Duration(seconds: 25);

/// Replies the model is not asked for: picking between names needs the
/// buttons, and small talk has nothing to ground.
const _rulesOnly = {
  ReplyKind.clarify,
  ReplyKind.hi,
  ReplyKind.thanks,
  ReplyKind.bye,
  ReplyKind.help,
};

/// [fallback] (Ask's answer without a model) re-worded by [generator] from
/// [facts], or [fallback] itself whenever the model fails, takes longer than
/// [timeout], breaks the chart line's JSON or says a number the facts do not
/// have. The chart is drawn from the app's numbers, never the model's.
/// Never throws.
Future<AskAnswer> answerWithModel({
  required SlmGenerator generator,
  required String question,
  required SlmFacts facts,
  required AskAnswer fallback,
  Duration timeout = modelAnswerTimeout,
}) async {
  if (_rulesOnly.contains(fallback.kind) || facts.sections.isEmpty) {
    return fallback;
  }
  try {
    final reply =
        await _collect(
          generator.ask(system: slmSystem(facts), question: question),
        ).timeout(
          timeout,
          onTimeout: () {
            generator.stop();
            return null;
          },
        );
    if (reply == null) return fallback;
    final parsed = SlmAnswer.parse(reply);
    final choice = parsed.choice;
    final text = parsed.text.trim();
    if (choice == null || text.isEmpty) return fallback;
    if (ungroundedNumbers(text, facts.text).isNotEmpty) return fallback;
    final input = facts.input;
    final chart = choice.draws && input != null
        ? askChartFor(choice, slmChartPoints(input, choice))
        : null;
    return fallback.byModel(text, chart);
  } on Object {
    return fallback;
  }
}

/// The whole reply, or null when it failed.
Future<String?> _collect(Stream<SlmEvent> events) async {
  final text = StringBuffer();
  await for (final event in events) {
    switch (event) {
      case SlmPiece(text: final piece):
        text.write(piece);
      case SlmDone():
        return text.toString();
      case SlmFailed():
        return null;
    }
  }
  return null;
}

/// [points] as one of Ask's charts: a split bar for fees, bars otherwise.
/// Null when there is nothing to draw.
AskChart? askChartFor(SlmChoice choice, List<SlmPoint> points) {
  if (points.isEmpty) return null;
  if (choice.data == SlmData.fees && points.length == 2) {
    final fees = points[0].amountMinor;
    final whole = fees + points[1].amountMinor;
    if (fees <= 0 || whole <= 0) return null;
    return AskChart.share(
      partMinor: fees,
      wholeMinor: whole,
      partLabel: points[0].label,
      restLabel: points[1].label,
    );
  }
  final bars = [
    for (final (i, p) in points.indexed)
      AskBar(
        p.label,
        // Money in and out by week: the bar is what went out.
        choice.data == SlmData.in_out_weeks
            ? p.secondMinor ?? 0
            : p.amountMinor,
        highlight: choice.data == SlmData.months_trend
            ? i == points.length - 1
            : i == 0,
      ),
  ];
  if (bars.every((b) => b.valueMinor <= 0)) return null;
  return AskChart.bars(bars);
}
