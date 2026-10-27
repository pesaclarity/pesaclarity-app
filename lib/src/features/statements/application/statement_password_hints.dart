import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../sms/application/sms_capture_providers.dart';

/// Approved password hints, by the key a statement pack names in its
/// `password_hint`. Packs carry only the key, so all wording stays here.
const statementPasswordHints = {
  'mpesa_statement':
      'Safaricom sends the password by SMS when you request a statement.',
};

/// Hints for the statements of the institutions the person ticked in My
/// accounts, or of every institution when none is ticked. An encrypted PDF
/// cannot be read before it opens, so the app cannot tell whose it is.
final statementPasswordHintsProvider = Provider<List<String>>((ref) {
  final selected = {
    for (final institution in ref.watch(selectedInstitutionsProvider))
      institution.id,
  };
  final hints = <String>{};
  for (final pack in loadBundledStatementPacks()) {
    final key = pack.passwordHint;
    if (key == null) continue;
    if (selected.isNotEmpty && !selected.contains(pack.institution)) continue;
    final hint = statementPasswordHints[key];
    if (hint != null) hints.add(hint);
  }
  return hints.toList();
});
