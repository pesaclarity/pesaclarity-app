import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/backup/backup.dart';

/// Hands files and text to other apps through the Android share sheet.
abstract interface class FileSharer {
  Future<void> shareFile(File file, {required String subject, String? text});

  Future<void> shareText(String text, {required String subject});
}

class SharePlusFileSharer implements FileSharer {
  const SharePlusFileSharer();

  @override
  Future<void> shareFile(
    File file, {
    required String subject,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject, text: text),
    );
  }

  @override
  Future<void> shareText(String text, {required String subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}

/// Sends a PDF to the system print screen.
abstract interface class DocumentPrinter {
  Future<void> printPdf(Uint8List bytes, {required String name});
}

class SystemDocumentPrinter implements DocumentPrinter {
  const SystemDocumentPrinter();

  @override
  Future<void> printPdf(Uint8List bytes, {required String name}) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
}

/// The recovery key as plain text, for saving or sharing.
String recoveryKeyText(RecoveryKey key, DateTime createdAt) {
  final date =
      '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-'
      '${createdAt.day.toString().padLeft(2, '0')}';
  return '''
Pesa Clarity recovery key

${key.toDisplayString()}

Made on $date.

This key opens your Pesa Clarity backups if you forget your passphrase.
Keep it somewhere safe and private, such as printed at home.
Anyone with this key and a copy of your backup can read your data.
''';
}

/// The recovery key as a one-page PDF, for printing or saving.
Future<Uint8List> recoveryKeyPdf(RecoveryKey key, DateTime createdAt) {
  final groups = key.toDisplayString().split('-');
  final lines = [
    for (var i = 0; i < groups.length; i += 4)
      groups
          .sublist(i, i + 4 > groups.length ? groups.length : i + 4)
          .join('  '),
  ];
  final date =
      '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-'
      '${createdAt.day.toString().padLeft(2, '0')}';
  final doc = pw.Document(title: 'Pesa Clarity recovery key')
    ..addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Pesa Clarity recovery key',
              style: const pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Made on $date'),
            pw.SizedBox(height: 32),
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text(
                        line,
                        style: pw.TextStyle(
                          font: pw.Font.courierBold(),
                          fontSize: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 32),
            pw.Text(
              'This key opens your Pesa Clarity backups if you forget your '
              'passphrase. Keep it somewhere safe and private.',
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Anyone with this key and a copy of your backup can read your '
              'data.',
            ),
          ],
        ),
      ),
    );
  return doc.save();
}
