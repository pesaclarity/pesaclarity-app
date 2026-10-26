import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/enums.dart';

/// A bank or mobile money provider whose SMS the app can read.
@immutable
class Institution {
  const Institution({
    required this.id,
    required this.name,
    required this.type,
    required this.senderIds,
  });

  /// The ujumbe parser pack id, such as `mpesa`.
  final String id;
  final String name;
  final AccountType type;

  /// SMS sender IDs this institution sends alerts from.
  final List<String> senderIds;
}

/// Institutions offered in My accounts, in display order.
///
/// TODO(ujumbe): build this from the bundled parser packs (id, name, senders)
/// once the ujumbe dependency is enabled.
const institutionCatalogue = [
  Institution(
    id: 'mpesa',
    name: 'M-Pesa',
    type: AccountType.mpesa,
    senderIds: ['MPESA'],
  ),
  Institution(
    id: 'im_bank',
    name: 'I&M Bank',
    type: AccountType.bank,
    senderIds: ['I&M'],
  ),
  Institution(
    id: 'kcb',
    name: 'KCB',
    type: AccountType.bank,
    senderIds: ['KCB'],
  ),
];

final institutionCatalogueProvider = Provider<List<Institution>>(
  (ref) => institutionCatalogue,
);
