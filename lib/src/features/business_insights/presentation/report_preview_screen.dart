import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../shared/widgets/states.dart';
import '../../printing/presentation/print_sheet.dart';
import '../application/report_content.dart';
import '../application/report_maker.dart';

/// The report's PDF as it will be shared, with Share and CSV under it.
class ReportPreviewScreen extends ConsumerStatefulWidget {
  const ReportPreviewScreen({required this.doc, required this.pdf, super.key});

  final ReportDocument doc;
  final Uint8List pdf;

  @override
  ConsumerState<ReportPreviewScreen> createState() =>
      _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends ConsumerState<ReportPreviewScreen> {
  var _busy = false;

  Future<void> _share({required bool csv}) async {
    setState(() => _busy = true);
    try {
      final maker = ref.read(reportMakerProvider);
      if (csv) {
        await maker.shareCsv(widget.doc);
      } else {
        await maker.sharePdf(widget.doc);
      }
    } on Object {
      if (mounted) showNote(context, 'The report was not shared. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.doc.title)),
    body: Column(
      children: [
        Expanded(
          child: PdfPreview(
            build: (_) async => widget.pdf,
            useActions: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName: widget.doc.fileName('pdf'),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('preview-share'),
                    onPressed: _busy ? null : () => _share(csv: false),
                    child: const Text('Share PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const Key('preview-print'),
                  onPressed: _busy
                      ? null
                      : () => showPrintSheet(
                          context,
                          title: 'Print report',
                          subtitle: widget.doc.title,
                          name: widget.doc.fileName('pdf'),
                          pdf: () async => widget.pdf,
                          fullPage: true,
                        ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('preview-csv'),
                  onPressed: _busy ? null : () => _share(csv: true),
                  child: const Text('CSV'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
