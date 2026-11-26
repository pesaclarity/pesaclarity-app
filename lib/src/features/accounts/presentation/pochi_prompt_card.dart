import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../savings/presentation/savings_prompt_card.dart';
import '../../savings/presentation/savings_text.dart';
import '../application/pochi_ask.dart';

/// "You have Pochi la Biashara. Add it?" (decision 0026 item 5), at the top
/// of Activity in the space that read its messages: the same question as a
/// savings app's, on a card of its own, as the payments it is about wait
/// off the records. Add makes the account and reads them onto it; "Not now"
/// stops the question there for good.
class PochiPromptCard extends ConsumerStatefulWidget {
  const PochiPromptCard(this.waiting, {super.key});

  final PochiWaiting waiting;

  @override
  ConsumerState<PochiPromptCard> createState() => _PochiPromptCardState();
}

class _PochiPromptCardState extends ConsumerState<PochiPromptCard> {
  var _busy = false;

  Future<void> _answer(Future<String> Function() answer) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final said = await answer();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(said)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ask = ref.read(pochiAskProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AskCard(
        key: const Key('pochi-prompt'),
        attached: false,
        title: SavingsText.pochiTitle,
        body: SavingsText.pochiBody(widget.waiting.payments),
        primary: FilledButton(
          key: const Key('pochi-prompt-add'),
          onPressed: _busy
              ? null
              : () => _answer(
                  () async => SavingsText.pochiAdded(await ask.add()),
                ),
          child: const Text(SavingsText.addPochi),
        ),
        secondary: OutlinedButton(
          key: const Key('pochi-prompt-decline'),
          onPressed: _busy
              ? null
              : () => _answer(() async {
                  await ask.decline();
                  return SavingsText.pochiDeclined;
                }),
          child: const Text(SavingsText.notNow),
        ),
      ),
    );
  }
}
