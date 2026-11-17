import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../application/read_again.dart';

/// `Equity`, `Equity and KCB`, `Equity, KCB and M-Pesa`.
String namesList(List<String> names) => switch (names) {
  [] => '',
  [final one] => one,
  _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
};

/// "Newer readers found 12 payments", on Home after messages were read
/// again on their own and something changed, until it is closed.
class ReadAgainHomeCard extends ConsumerWidget {
  const ReadAgainHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(readAgainNoticeProvider).value;
    if (notice == null) return const SizedBox.shrink();
    final names = {
      for (final i in ref.watch(institutionCatalogueProvider)) i.id: i.name,
    };
    String payments(int n) => n == 1 ? '1 payment' : '$n payments';
    final title = notice.added > 0
        ? 'Newer readers found ${payments(notice.added)}'
        : 'Newer readers updated ${payments(notice.updated)}';
    final banks = namesList([
      for (final id in notice.institutionIds) ?names[id],
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-read-again'),
          title: Text(title),
          subtitle: banks.isEmpty
              ? null
              : Text('Messages from $banks were read again'),
          trailing: IconButton(
            key: const Key('home-read-again-close'),
            tooltip: 'Close',
            icon: Icon(
              Icons.close,
              size: 20,
              color: PesaColors.of(context).textMuted,
            ),
            onPressed: () => closeReadAgainNotice(ref),
          ),
        ),
      ),
    );
  }
}
