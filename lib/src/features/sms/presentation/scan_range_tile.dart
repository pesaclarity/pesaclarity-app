import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../application/scan_range_provider.dart';
import '../domain/scan_range.dart';

/// "We read every message these accounts have sent." for the range.
String scanRangeSentence(ScanRange range) => switch (range.period) {
  ScanPeriod.all => 'We read every message these accounts have sent.',
  ScanPeriod.since => 'We read messages ${range.label.toLowerCase()}.',
  _ => 'We read messages from the ${range.label.toLowerCase()}.',
};

/// "Read messages from", with the period as a drop-down.
class ScanRangeTile extends ConsumerWidget {
  const ScanRangeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(scanRangeProvider).value ?? ScanRange.all;
    return Card(
      child: ListTile(
        title: const Text('Read messages from'),
        subtitle: const Text(
          'For every account you ticked. New messages are always added.',
        ),
        trailing: ChoiceMenu<ScanPeriod>(
          key: const Key('scan-range'),
          name: 'Read messages from',
          options: [
            for (final period in ScanPeriod.values)
              (
                period,
                period == ScanPeriod.since && range.period == ScanPeriod.since
                    ? range.label
                    : period.label,
              ),
          ],
          value: range.period,
          itemKey: (period) => Key('scan-range-${period.name}'),
          onChanged: (period) => _choose(context, ref, range, period),
        ),
      ),
    );
  }
}

/// Saves [period]; "From a date" first asks for the first day.
Future<void> _choose(
  BuildContext context,
  WidgetRef ref,
  ScanRange current,
  ScanPeriod period,
) async {
  final notifier = ref.read(scanRangeProvider.notifier);
  if (period != ScanPeriod.since) {
    await notifier.choose(ScanRange(period));
    return;
  }
  final today = CalendarDate.local(ref.read(clockProvider)());
  final start = current.since ?? today.yearMonth.addMonths(-1).firstDay;
  final picked = await pickDate(
    context,
    initialDate: DateTime(start.year, start.month, start.day),
    firstDate: DateTime(2000),
    lastDate: DateTime(today.year, today.month, today.day),
  );
  if (picked == null) return;
  await notifier.choose(
    ScanRange(
      ScanPeriod.since,
      since: CalendarDate(picked.year, picked.month, picked.day),
    ),
  );
}
