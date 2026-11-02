import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../application/scan_range_provider.dart';
import '../domain/scan_range.dart';

/// "We read every message these accounts have sent." for the range.
String scanRangeSentence(ScanRange range) => switch (range.period) {
  ScanPeriod.all => 'We read every message these accounts have sent.',
  ScanPeriod.since => 'We read messages ${range.label.toLowerCase()}.',
  _ => 'We read messages from the ${range.label.toLowerCase()}.',
};

/// "Read messages from · All messages": opens the choice.
class ScanRangeTile extends ConsumerWidget {
  const ScanRangeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(scanRangeProvider).value ?? ScanRange.all;
    return Card(
      child: ListTile(
        key: const Key('scan-range'),
        title: const Text('Read messages from'),
        subtitle: Text(range.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showScanRangeSheet(context, ref),
      ),
    );
  }
}

Future<void> showScanRangeSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(scanRangeProvider).value ?? ScanRange.all;
  final chosen = await showModalBottomSheet<ScanRange>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScanRangeSheet(current),
  );
  if (chosen != null) {
    await ref.read(scanRangeProvider.notifier).choose(chosen);
  }
}

class _ScanRangeSheet extends ConsumerStatefulWidget {
  const _ScanRangeSheet(this.current);

  final ScanRange current;

  @override
  ConsumerState<_ScanRangeSheet> createState() => _ScanRangeSheetState();
}

class _ScanRangeSheetState extends ConsumerState<_ScanRangeSheet> {
  late var _range = widget.current;

  Future<void> _pick(ScanPeriod period) async {
    if (period != ScanPeriod.since) {
      setState(() => _range = ScanRange(period));
      return;
    }
    final today = CalendarDate.local(ref.read(clockProvider)());
    final start = _range.since ?? today.yearMonth.addMonths(-1).firstDay;
    final picked = await pickDate(
      context,
      initialDate: DateTime(start.year, start.month, start.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _range = ScanRange(
        ScanPeriod.since,
        since: CalendarDate(picked.year, picked.month, picked.day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Read messages from', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'For every account you ticked. New messages are always added.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            RadioGroup<ScanPeriod>(
              groupValue: _range.period,
              onChanged: (p) => p == null ? null : _pick(p),
              child: Column(
                children: [
                  for (final period in ScanPeriod.values)
                    RadioListTile<ScanPeriod>(
                      key: Key('scan-range-${period.name}'),
                      value: period,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        period == ScanPeriod.since &&
                                _range.period == ScanPeriod.since
                            ? _range.label
                            : period.label,
                      ),
                      subtitle: switch (period) {
                        ScanPeriod.all => const Text(
                          'Everything on this phone',
                        ),
                        ScanPeriod.since => const Text('Pick the first day'),
                        _ => null,
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('scan-range-done'),
              onPressed: () => Navigator.pop(context, _range),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
