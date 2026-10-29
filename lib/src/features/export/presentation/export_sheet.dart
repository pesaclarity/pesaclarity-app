import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../../payees/application/payee_providers.dart';
import '../../payees/application/tag_filter.dart';
import '../application/export_service.dart';

/// The Export button for a screen header: one tap opens the formats, a
/// second exports and opens the share sheet.
class ExportButton extends ConsumerWidget {
  const ExportButton({required this.scope, this.label = 'Export', super.key});

  /// What to export, read when tapped so it follows the current filters.
  final ExportScope Function() scope;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: OutlinedButton.icon(
      onPressed: () => showExportSheet(context, scope()),
      icon: const Icon(Icons.file_download_outlined, size: 20),
      label: Text(label),
    ),
  );
}

/// Asks which format, then builds the export for [scope] and shares it.
Future<void> showExportSheet(BuildContext context, ExportScope scope) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ExportSheet(scope: scope),
    );

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({required this.scope, super.key});

  final ExportScope scope;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportFormat? _busy;

  Future<void> _export(ExportFormat format) async {
    setState(() => _busy = format);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(exportServiceProvider).share(widget.scope, format);
      if (mounted) navigator.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _busy = null);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Export did not finish. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final isWorkbook = widget.scope is FullWorkbookExport;

    String detail(ExportFormat format) => switch (format) {
      ExportFormat.csv when isWorkbook => 'One CSV file per table, zipped',
      ExportFormat.csv => 'Opens in any spreadsheet app',
      ExportFormat.xlsx when isWorkbook =>
        'Every table and tag, one sheet each',
      ExportFormat.xlsx => 'With totals by category and tag',
      ExportFormat.pdf => 'Ready to print or send',
    };

    IconData icon(ExportFormat format) => switch (format) {
      ExportFormat.csv => Icons.description_outlined,
      ExportFormat.xlsx => Icons.grid_on_outlined,
      ExportFormat.pdf => Icons.picture_as_pdf_outlined,
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.scope.title,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            for (final format in ExportFormat.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: _busy == null,
                leading: Icon(icon(format)),
                title: Text(format.label),
                subtitle: Text(detail(format)),
                trailing: _busy == format
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.ios_share),
                onTap: () => _export(format),
              ),
            const SizedBox(height: 4),
            Text(
              'Made on this phone. You choose where it goes.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Activity's Export button: every transaction, narrowed to the tag Activity
/// is filtered to.
class ActivityExportButton extends ConsumerWidget {
  const ActivityExportButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ExportButton(
    scope: () {
      final tagId = ref.read(activityTagFilterProvider);
      final tag = tagId == null
          ? null
          : ref
                .read(tagUsageProvider)
                .value
                ?.where((u) => u.tag.id == tagId)
                .firstOrNull
                ?.tag
                .name;
      return TransactionsExport(
        title: tag == null ? 'Activity' : 'Activity, #$tag',
        fileStem: 'activity',
        tagId: tagId,
      );
    },
  );
}
