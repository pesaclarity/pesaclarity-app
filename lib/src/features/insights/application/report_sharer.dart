import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a finished PDF to the phone's share sheet.
abstract interface class ReportSharer {
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  });
}

/// Writes the PDF to the app's cache, then opens Android's share sheet.
class SharePlusReportSharer implements ReportSharer {
  const SharePlusReportSharer();

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: subject,
      ),
    );
  }
}

final reportSharerProvider = Provider<ReportSharer>(
  (ref) => const SharePlusReportSharer(),
);
