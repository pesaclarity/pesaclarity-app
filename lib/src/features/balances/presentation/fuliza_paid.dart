import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../debts/application/debts_overview_provider.dart';
import 'balance_text.dart';

/// Records that the Fuliza owed on M-Pesa account [accountId] is paid, as
/// the person says, then offers to undo it. The wallet stays at
/// [walletMinor]; [owedMinor] stops being owed.
Future<void> markFulizaPaid(
  ScaffoldMessengerState messenger,
  ProviderContainer ref, {
  required int accountId,
  required int walletMinor,
  required int owedMinor,
  required String currency,
}) async {
  final repository = ref.read(balancesRepositoryProvider);
  final id = await repository.markFulizaPaid(
    accountId,
    walletMinor: walletMinor,
    owedMinor: owedMinor,
    at: ref.read(clockProvider)(),
    currency: currency,
  );
  ref.invalidate(debtsOverviewProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text(BalanceText.fulizaMarkedPaid),
        action: SnackBarAction(
          label: BalanceText.undo,
          onPressed: () async {
            await repository.undoCorrection(id);
            ref.invalidate(debtsOverviewProvider);
          },
        ),
      ),
    );
}

/// "Fuliza is paid": the way out when the app still counts Fuliza the
/// person has repaid.
class FulizaPaidButton extends ConsumerWidget {
  const FulizaPaidButton({
    required this.accountId,
    required this.walletMinor,
    required this.owedMinor,
    required this.currency,
    this.onDone,
    super.key,
  });

  final int accountId;
  final int walletMinor;
  final int owedMinor;
  final String currency;

  /// Runs before it is recorded, such as closing a sheet.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    key: const Key('fuliza-is-paid'),
    icon: const Icon(Icons.check_circle_outline),
    onPressed: () {
      // The sheet may close first; the messenger and container outlive it.
      final messenger = ScaffoldMessenger.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      onDone?.call();
      markFulizaPaid(
        messenger,
        container,
        accountId: accountId,
        walletMinor: walletMinor,
        owedMinor: owedMinor,
        currency: currency,
      );
    },
    label: const Text(BalanceText.fulizaIsPaid),
  );
}
