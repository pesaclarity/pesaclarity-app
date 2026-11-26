import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../../core/share/share_codec.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';

/// Reads a join request or an invite from the other phone's QR code.
abstract interface class ShareCodeScanner {
  /// The code's text once it reads as [expect]; null if the person backs
  /// out.
  Future<String?> scan(BuildContext context, ShareCodeKind expect);
}

/// The camera, through zxing-cpp (flutter_zxing): no Google ML Kit, so the
/// play and foss builds use the same scanner.
class CameraShareCodeScanner implements ShareCodeScanner {
  const CameraShareCodeScanner();

  @override
  Future<String?> scan(BuildContext context, ShareCodeKind expect) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ShareScanScreen(expect: expect)),
      );
}

final shareCodeScannerProvider = Provider<ShareCodeScanner>(
  (ref) => const CameraShareCodeScanner(),
);

/// What a scanned [text] is, when it is [expect]; otherwise why not, in
/// words. The same check as for a file.
String? scannedProblem(String? text, ShareCodeKind expect) {
  final want = expect == ShareCodeKind.joinRequest
      ? 'a join request'
      : 'an invite';
  if (text == null) return "That code can't be read. Try again.";
  try {
    return readShareCode(text) == expect ? null : "That code isn't $want.";
  } on ShareFileException {
    return "That code isn't $want.";
  }
}

/// The camera, full screen, until a code of the right kind is read.
class ShareScanScreen extends StatefulWidget {
  const ShareScanScreen({required this.expect, super.key});

  final ShareCodeKind expect;

  @override
  State<ShareScanScreen> createState() => _ShareScanScreenState();
}

class _ShareScanScreenState extends State<ShareScanScreen> {
  String? _problem;
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final join = widget.expect == ShareCodeKind.joinRequest;
    return Scaffold(
      appBar: AppBar(
        title: Text(join ? 'Scan their join request' : 'Scan the invite'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Layout.gutter,
              0,
              Layout.gutter,
              12,
            ),
            child: Text(
              'Pesa Clarity uses the camera only to read this code. Nothing '
              'from the camera is kept or leaves this phone.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Layout.gutter),
              child: Text(_problem!, key: const Key('scan-problem')),
            ),
          Expanded(
            child: ReaderWidget(
              codeFormat: Format.qrCode,
              showGallery: false,
              showToggleCamera: false,
              onScan: (code) {
                if (_done) return;
                final problem = scannedProblem(code.text, widget.expect);
                if (problem == null) {
                  _done = true;
                  Navigator.of(context).pop(code.text!.trim());
                } else {
                  setState(() => _problem = problem);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
