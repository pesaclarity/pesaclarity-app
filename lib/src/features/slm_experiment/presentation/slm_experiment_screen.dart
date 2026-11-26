import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/slm_facts_loader.dart';
import '../data/slm_generator.dart';
import '../data/slm_model_licence.dart';
import '../domain/slm_answer.dart';
import '../domain/slm_facts.dart';
import 'slm_chart_view.dart';

/// The model the screen talks to: rayo only, closed with the screen.
final slmGeneratorProvider = Provider.autoDispose<SlmGenerator>((ref) {
  final generator = RayoSlmGenerator();
  ref.onDispose(generator.close);
  return generator;
});

/// The words on the screen.
abstract final class SlmStrings {
  static const title = 'Phone model (experiment)';
  static const profileRow = 'Try the on-phone language model (experiment)';
  static const profileRowDetail = 'Test builds only. Runs on this phone';
  static const privacy =
      'Runs on this phone. Nothing you type or see here leaves it, '
      'and nothing is saved.';
  static const presets = [
    'Where did my money go this month?',
    'How can I spend less?',
    'Am I on track with my budget?',
  ];
  static const hint = 'Ask about your money';
  static const ask = 'Ask';
  static const stop = 'Stop';
  static const clear = 'Clear';
  static const saw = 'What the model saw';
  static const caution =
      'A small model can get things wrong: check its numbers against '
      '"What the model saw".';
  static const licence = 'Model licence';
  static const check = 'Check this number';
  static const choseChart = 'Chart it picked';
  static const noChart = 'No chart: its first line was not the chart schema';
}

/// The words of a reply as it comes in: the chart line is hidden once it
/// starts with `{`, and its words appear after it.
String slmShownWhileRunning(String raw) {
  final t = raw.trimLeft();
  if (!t.startsWith('{')) return t;
  final nl = t.indexOf('\n');
  return nl < 0 ? '' : t.substring(nl + 1).trimLeft();
}

class _Turn {
  _Turn(this.question, this.facts);

  final String question;
  final SlmFacts facts;
  final StringBuffer answer = StringBuffer();
  SlmStats? stats;
  String? error;
  bool running = true;
}

/// A test-only screen: questions about the person's own money, answered by
/// a small language model on rayo from facts the app works out.
class SlmExperimentScreen extends ConsumerStatefulWidget {
  const SlmExperimentScreen({super.key});

  @override
  ConsumerState<SlmExperimentScreen> createState() =>
      _SlmExperimentScreenState();
}

class _SlmExperimentScreenState extends ConsumerState<SlmExperimentScreen> {
  final _input = TextEditingController();
  final _turns = <_Turn>[];
  StreamSubscription<SlmEvent>? _reply;

  bool get _running => _turns.isNotEmpty && _turns.last.running;

  @override
  void dispose() {
    unawaited(_reply?.cancel());
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    question = question.trim();
    if (question.isEmpty || _running) return;
    _input.clear();
    final SlmFacts facts;
    try {
      facts = await ref.read(slmFactsProvider.future);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _turns.add(
          _Turn(question, const SlmFacts([]))
            ..running = false
            ..error = 'Could not read your records: $e',
        ),
      );
      return;
    }
    if (!mounted) return;
    final turn = _Turn(question, facts);
    setState(() => _turns.add(turn));
    final generator = ref.read(slmGeneratorProvider);
    _reply = generator
        .ask(system: slmSystem(facts), question: question)
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              switch (event) {
                case SlmPiece(:final text):
                  turn.answer.write(text);
                case SlmDone(:final stats):
                  turn
                    ..stats = stats
                    ..running = false;
                case SlmFailed(:final reason):
                  turn
                    ..error = reason
                    ..running = false;
              }
            });
          },
          onDone: () {
            if (mounted && turn.running) setState(() => turn.running = false);
          },
        );
  }

  void _stop() => ref.read(slmGeneratorProvider).stop();

  void _clear() {
    if (_running) _stop();
    setState(_turns.clear);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text(SlmStrings.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('slm-list'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Text(SlmStrings.privacy, style: muted),
                  const SizedBox(height: 12),
                  for (final q in SlmStrings.presets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        key: Key('slm-preset-${SlmStrings.presets.indexOf(q)}'),
                        onPressed: _running ? null : () => _ask(q),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(q),
                      ),
                    ),
                  for (final turn in _turns) _TurnView(turn: turn),
                  if (_turns.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(SlmStrings.caution, style: muted),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('slm-licence'),
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'PesaClarity',
                      ),
                      child: const Text(
                        '$slmModelName (Apache-2.0) · ${SlmStrings.licence}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  TextField(
                    key: const Key('slm-input'),
                    controller: _input,
                    enabled: !_running,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: const InputDecoration(
                      hintText: SlmStrings.hint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _running
                            ? OutlinedButton(
                                key: const Key('slm-stop'),
                                onPressed: _stop,
                                child: const Text(SlmStrings.stop),
                              )
                            : FilledButton(
                                key: const Key('slm-ask'),
                                onPressed: () => _ask(_input.text),
                                child: const Text(SlmStrings.ask),
                              ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('slm-clear'),
                        onPressed: _turns.isEmpty ? null : _clear,
                        child: const Text(SlmStrings.clear),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final raw = turn.answer.toString();
    final parsed = turn.running ? null : SlmAnswer.parse(raw);
    final answer = parsed?.text ?? slmShownWhileRunning(raw).trim();
    final choice = parsed?.choice;
    final input = turn.facts.input;
    final flagged = parsed == null
        ? const <String>[]
        : ungroundedNumbers(answer, turn.facts.text);
    final firstLine = raw.trimLeft().split('\n').first.trim();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You', style: muted),
            Text(turn.question, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Text('Model', style: muted),
            if (answer.isNotEmpty)
              SelectableText(answer, key: const Key('slm-answer'))
            else if (turn.running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (flagged.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in flagged)
                      Chip(
                        key: Key('slm-check-$n'),
                        avatar: const Icon(Icons.error_outline, size: 16),
                        label: Text('${SlmStrings.check}: $n'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            if (choice != null && choice.draws && input != null)
              SlmChartView(
                choice: choice,
                points: slmChartPoints(input, choice),
              ),
            if (turn.error != null)
              Text(
                turn.error!,
                key: const Key('slm-error'),
                style: theme.textTheme.bodyMedium,
              ),
            if (turn.facts.sections.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('slm-saw'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(
                    '${SlmStrings.saw} (${turn.facts.lineCount} facts)',
                    style: theme.textTheme.bodyMedium,
                  ),
                  children: [
                    SelectableText(turn.facts.text, style: muted),
                    if (parsed != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        choice != null
                            ? '${SlmStrings.choseChart}: $firstLine'
                            : SlmStrings.noChart,
                        key: const Key('slm-choice'),
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
            if (turn.stats != null)
              Text(turn.stats!.line, key: const Key('slm-stats'), style: muted),
          ],
        ),
      ),
    );
  }
}
