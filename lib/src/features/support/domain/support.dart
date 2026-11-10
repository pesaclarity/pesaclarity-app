/// Giving to Pesa Clarity: where the gift goes, when the Home card shows,
/// and the gifts the person has made. Giving never unlocks anything.
library;

/// Where gifts go, set at build time with
/// `--dart-define=PESACLARITY_SUPPORT_URL=https://...`. `{amount}` in it
/// stands for the amount in shillings, when the page can take one.
const supportUrlDefine = String.fromEnvironment('PESACLARITY_SUPPORT_URL');

/// The names or numbers a gift's M-Pesa message shows as the payee,
/// separated by commas: `--dart-define=PESACLARITY_SUPPORT_PAYEES=...`.
const supportPayeesDefine = String.fromEnvironment(
  'PESACLARITY_SUPPORT_PAYEES',
);

/// The page on what Pesa Clarity costs to run:
/// `--dart-define=PESACLARITY_SUPPORT_COSTS_URL=https://...`.
const supportCostsUrlDefine = String.fromEnvironment(
  'PESACLARITY_SUPPORT_COSTS_URL',
);

/// The amounts offered first, in shillings.
const supportAmounts = [50, 100, 200, 500];

/// The amount chosen first.
const supportDefaultAmount = 200;

/// How giving is set up in this build.
class SupportConfig {
  const SupportConfig({
    required this.template,
    this.payees = const {},
    this.costs,
  });

  /// The giving page's https address, perhaps with `{amount}`.
  final String template;

  /// Payee names and numbers, lower case.
  final Set<String> payees;

  /// What it costs to run, or null.
  final Uri? costs;

  /// Reads the build's settings. Null when there is no https giving page,
  /// so nothing about giving shows.
  static SupportConfig? parse({
    required String url,
    required String payees,
    required String costs,
  }) {
    final template = url.trim();
    if (!_isHttps(Uri.tryParse(template.replaceAll('{amount}', '1')))) {
      return null;
    }
    final costsUri = Uri.tryParse(costs.trim());
    return SupportConfig(
      template: template,
      payees: {
        for (final p in payees.split(','))
          if (p.trim().isNotEmpty) p.trim().toLowerCase(),
      },
      costs: _isHttps(costsUri) ? costsUri : null,
    );
  }

  /// Whether the page can be opened with an amount already chosen.
  bool get takesAmount => template.contains('{amount}');

  /// Whether the app can recognise a gift's M-Pesa message.
  bool get knowsGifts => payees.isNotEmpty;

  /// The page to open for [shillings]. The address carries the amount and
  /// nothing about the person.
  Uri link([int? shillings]) => Uri.parse(
    template.replaceAll('{amount}', shillings == null ? '' : '$shillings'),
  );

  /// Whether a payment to [name] or [number] is a gift to Pesa Clarity.
  bool isGiftTo({String? name, String? number}) =>
      (name != null && payees.contains(name.trim().toLowerCase())) ||
      (number != null && payees.contains(number.trim().toLowerCase()));
}

bool _isHttps(Uri? uri) =>
    uri != null && uri.isScheme('https') && uri.host.isNotEmpty;

/// One gift, read from its own M-Pesa message.
class Gift {
  const Gift({
    required this.id,
    required this.at,
    required this.amountMinor,
    this.code,
  });

  final int id;
  final DateTime at;
  final int amountMinor;

  /// The M-Pesa code, such as TK10000001.
  final String? code;
}

/// What the app remembers about giving, on this phone only.
class SupportState {
  const SupportState({
    this.firstSeenAt,
    this.showingSince,
    this.restUntil,
    this.optedOut = false,
    this.thanked = const {},
  });

  /// When this phone first opened a build that can ask.
  final DateTime? firstSeenAt;

  /// When the Home card started its current showing.
  final DateTime? showingSince;

  /// The card rests until then.
  final DateTime? restUntil;

  /// "Don't ask me again".
  final bool optedOut;

  /// Gifts already thanked, by id.
  final Set<int> thanked;

  SupportState copyWith({
    DateTime? firstSeenAt,
    DateTime? Function()? showingSince,
    DateTime? restUntil,
    bool? optedOut,
    Set<int>? thanked,
  }) => SupportState(
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    showingSince: showingSince == null ? this.showingSince : showingSince(),
    restUntil: restUntil ?? this.restUntil,
    optedOut: optedOut ?? this.optedOut,
    thanked: thanked ?? this.thanked,
  );

  static SupportState fromJson(Map<String, Object?>? json) {
    DateTime? at(String key) => switch (json?[key]) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    return SupportState(
      firstSeenAt: at('firstSeenAt'),
      showingSince: at('showingSince'),
      restUntil: at('restUntil'),
      optedOut: json?['optedOut'] == true,
      thanked: {
        for (final id in (json?['thanked'] as List<Object?>?) ?? const [])
          if (id is int) id,
      },
    );
  }

  Map<String, Object?> toJson() => {
    if (firstSeenAt case final at?) 'firstSeenAt': at.toUtc().toIso8601String(),
    if (showingSince case final at?)
      'showingSince': at.toUtc().toIso8601String(),
    if (restUntil case final at?) 'restUntil': at.toUtc().toIso8601String(),
    'optedOut': optedOut,
    'thanked': thanked.toList()..sort(),
  };
}

/// The card never asks in the first 30 days.
const supportFirstAfter = Duration(days: 30);

/// Each showing lasts 3 days.
const supportShowFor = Duration(days: 3);

/// Showings start at least 60 days apart.
const supportRestFor = Duration(days: 60);

/// Nobody who gave in the last six months is asked.
const supportAfterGift = Duration(days: 182);

/// A gift is thanked when its message arrives within this long.
const supportThankWithin = Duration(days: 14);

/// Whether the Home card shows now.
enum SupportCardTime {
  /// Not now.
  hidden,

  /// In a showing that has started.
  showing,

  /// A new showing starts now.
  startsNow,
}

/// When the Home card shows. [moneyTight] is true when today's money is
/// spent, the plan is used up or a payment may not go through: the card
/// never asks then.
SupportCardTime supportCardTime({
  required SupportState state,
  required DateTime now,
  required bool moneyTight,
  DateTime? lastGiftAt,
}) {
  final first = state.firstSeenAt;
  if (state.optedOut || first == null) return SupportCardTime.hidden;
  if (now.isBefore(first.add(supportFirstAfter))) {
    return SupportCardTime.hidden;
  }
  if (lastGiftAt != null && now.isBefore(lastGiftAt.add(supportAfterGift))) {
    return SupportCardTime.hidden;
  }
  if (moneyTight) return SupportCardTime.hidden;
  final since = state.showingSince;
  if (since != null && now.isBefore(since.add(supportShowFor))) {
    return SupportCardTime.showing;
  }
  final rest = state.restUntil;
  if (rest != null && now.isBefore(rest)) return SupportCardTime.hidden;
  return SupportCardTime.startsNow;
}

/// The newest gift not yet thanked whose message came in lately, or null.
Gift? giftToThank(List<Gift> gifts, SupportState state, DateTime now) {
  for (final gift in gifts) {
    if (state.thanked.contains(gift.id)) continue;
    if (now.difference(gift.at) > supportThankWithin) continue;
    return gift;
  }
  return null;
}
