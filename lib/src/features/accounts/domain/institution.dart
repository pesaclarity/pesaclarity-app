import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../domain/enums.dart';

/// A bank or mobile money provider whose SMS the app can read, backed by
/// its ujumbe parser pack.
@immutable
class Institution {
  const Institution(this.pack, {required this.type});

  /// Builds an institution from its parser [pack].
  factory Institution.fromPack(ParserPack pack) =>
      Institution(pack, type: _accountTypes[pack.id] ?? AccountType.bank);

  /// The parser pack that reads this institution's messages.
  final ParserPack pack;
  final AccountType type;

  /// The parser pack id, such as `mpesa`.
  String get id => pack.id;
  String get name => pack.name;

  /// SMS sender IDs this institution sends alerts from.
  List<String> get senderIds => pack.senders;
}

// Packs say nothing about the kind of account; anything not listed is a bank.
const _accountTypes = {'mpesa': AccountType.mpesa};

/// Institutions offered in My accounts, one per bundled parser pack: mobile
/// money first, then by name.
final List<Institution> institutionCatalogue = catalogueFromPacks(
  loadBundledPacks(),
);

/// The institutions for [packs], in display order.
List<Institution> catalogueFromPacks(Iterable<ParserPack> packs) {
  int rank(Institution i) => i.type == AccountType.mpesa ? 0 : 1;
  return [for (final pack in packs) Institution.fromPack(pack)]..sort(
    (a, b) => rank(a) != rank(b)
        ? rank(a) - rank(b)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
}

final institutionCatalogueProvider = Provider<List<Institution>>(
  (ref) => institutionCatalogue,
);
