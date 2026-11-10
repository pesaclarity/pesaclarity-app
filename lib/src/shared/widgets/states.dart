import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';

/// The spinner while something loads. [inList] for one under a tab's title
/// row; otherwise it fills the screen below the app bar.
class LoadingView extends StatelessWidget {
  const LoadingView({this.inList = false, super.key});

  final bool inList;

  @override
  Widget build(BuildContext context) {
    const spinner = Center(child: CircularProgressIndicator.adaptive());
    return inList
        ? const Padding(padding: EdgeInsets.all(32), child: spinner)
        : spinner;
  }
}

/// What shows when something could not load: [message], such as "Your
/// goals could not load.", and Try again.
class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

/// A short line where a list has nothing yet, such as "Sales show here."
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium!
          .copyWith(color: PesaColors.of(context).textMuted),
    ),
  );
}

/// A short message at the bottom of the screen, such as "Sale saved." It
/// replaces one already showing.
void showNote(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
