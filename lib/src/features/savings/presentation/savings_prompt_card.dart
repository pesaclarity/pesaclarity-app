import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_prompt.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../debts/presentation/due_line.dart' show IconLine;
import 'add_savings_sheet.dart';
import 'savings_text.dart';

/// The payment a question is asked under, drawn as the top of a card that
/// [SavingsPromptCard] finishes, so the two read as one.
class SavingsPromptRow extends StatelessWidget {
  const SavingsPromptRow({required this.child, super.key});

  /// The payment's row, as Activity draws it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        border: Border.all(color: PesaColors.of(context).border),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(BrandTokens.cardRadius),
        ),
      ),
      child: child,
    );
  }
}

/// "Is this your Chumz savings?", under the payment it is about: Add Chumz
/// opens the sheet that adds it, and "It's not mine" stops the question for
/// good, leaving the payment as it is.
///
/// For an M-Pesa family member (decision 0026 item 5), the same question in
/// its own words, "You have Ziidi. Add it?", under its newest move: Add
/// makes the account at once and turns every move into a transfer, and
/// "Not now" stops the question for good, counting the moves as before.
class SavingsPromptCard extends ConsumerWidget {
  const SavingsPromptCard(this.prompt, {super.key});

  final SavingsPrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = prompt.product;
    final family = product.keptOnItsOwn;
    Future<void> decline() async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      await ref.read(savingsRepositoryProvider).decline(product.id);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              family
                  ? SavingsText.familyDeclined(product)
                  : SavingsText.declined(product),
            ),
          ),
        );
    }

    return AskCard(
      key: const Key('savings-prompt'),
      title: family
          ? SavingsText.familyTitle(product)
          : SavingsText.promptTitle(product),
      body: family
          ? SavingsText.familyBody(product)
          : SavingsText.promptBody(product, prompt.paidTo),
      primary: FilledButton(
        key: const Key('savings-prompt-add'),
        onPressed: family
            ? () => ref
                  .read(savingsRepositoryProvider)
                  .add(
                    product,
                    at: ref.read(clockProvider)(),
                    promptedTransactionId: prompt.transactionId,
                  )
            : () => showAddSavingsSheet(
                context,
                product,
                promptedTransactionId: prompt.transactionId,
              ),
        child: Text(SavingsText.add(product)),
      ),
      secondary: OutlinedButton(
        key: const Key('savings-prompt-decline'),
        onPressed: decline,
        child: Text(family ? SavingsText.notNow : SavingsText.notMine),
      ),
    );
  }
}

/// A question with its answers, drawn as the bottom of a card whose top is
/// the row it is about ([SavingsPromptRow]); with [attached] false, as a
/// card of its own, for a question about no one row.
class AskCard extends StatelessWidget {
  const AskCard({
    required this.title,
    required this.body,
    required this.primary,
    required this.secondary,
    this.attached = true,
    super.key,
  });

  final String title;
  final String body;
  final Widget primary;
  final Widget secondary;
  final bool attached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    const radius = Radius.circular(BrandTokens.cardRadius);
    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        border: Border.all(color: colors.border),
        borderRadius: attached
            ? const BorderRadius.vertical(bottom: radius)
            : const BorderRadius.all(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: IconLine(
              icon: Icons.account_balance_outlined,
              iconColor: colors.link,
              iconSize: 20,
              gap: 10,
              text: TextSpan(text: title),
              style: theme.textTheme.titleMedium!,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          _Buttons(primary: primary, secondary: secondary),
        ],
      ),
    );
    // Drawn one pixel up, so its top edge is the row's bottom edge.
    return attached
        ? Transform.translate(offset: const Offset(0, -1), child: card)
        : card;
  }
}

/// Two buttons sharing the width while both labels fit on one line; with
/// large text, one under the other.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.primary, required this.secondary});

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
      if (scale > 1.3 || constraints.maxWidth < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primary, const SizedBox(height: 8), secondary],
        );
      }
      return Row(
        children: [
          Expanded(child: primary),
          const SizedBox(width: 10),
          Expanded(child: secondary),
        ],
      );
    },
  );
}

/// The line shown once under the payment after the product was added:
/// "Chumz added · 4 older payments updated". Marks itself seen.
class SavingsAddedLine extends ConsumerStatefulWidget {
  const SavingsAddedLine(this.notice, {required this.name, super.key});

  final SavingsAddedNotice notice;

  /// The account's name, such as Chumz.
  final String name;

  @override
  ConsumerState<SavingsAddedLine> createState() => _SavingsAddedLineState();
}

class _SavingsAddedLineState extends ConsumerState<SavingsAddedLine> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(savingsRepositoryProvider).markAddedNoticeSeen());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Padding(
      key: const Key('savings-added'),
      padding: const EdgeInsetsDirectional.only(start: 58, bottom: 6),
      child: IconLine(
        icon: Icons.check_circle_outline,
        iconSize: 16,
        gap: 8,
        text: TextSpan(
          text: SavingsText.added(widget.name, widget.notice.updated),
        ),
        style: theme.textTheme.bodySmall!.copyWith(
          color: colors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
