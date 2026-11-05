/// How a reminder is sent: the owner always taps send in that app.
enum SendWith {
  whatsapp('WhatsApp'),
  sms('SMS');

  const SendWith(this.label);

  final String label;
}

/// A reminder message the owner can edit. Fields in braces fill in on their
/// own; see [fillTemplate].
class ReminderTemplate {
  const ReminderTemplate({
    required this.id,
    required this.name,
    required this.text,
  });

  final String id;
  final String name;
  final String text;

  ReminderTemplate copyWith({String? name, String? text}) => ReminderTemplate(
    id: id,
    name: name ?? this.name,
    text: text ?? this.text,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'text': text};

  static ReminderTemplate? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'], text = json['text'];
    if (id is! String || name is! String || text is! String) return null;
    return ReminderTemplate(id: id, name: name, text: text);
  }
}

/// The three starting messages from the spec, in [currency].
List<ReminderTemplate> defaultTemplates(String currency) => [
  ReminderTemplate(
    id: 'friendly',
    name: 'Friendly',
    text:
        'Hi {name}, a friendly reminder from {business}: $currency {amount} '
        'for {what}, due {due}. You can pay to till {till}. Thank you!',
  ),
  ReminderTemplate(
    id: 'due_today',
    name: 'Due today',
    text:
        'Hi {name}, $currency {amount} is due today. Pay to till {till} when '
        'you can. Thank you!',
  ),
  ReminderTemplate(
    id: 'a_while',
    name: "It's been a while",
    text:
        'Hi {name}, just checking in on $currency {amount} from {date}. Pay '
        'to till {till} when you can. Thank you!',
  ),
];

/// The fields a template can use.
const reminderFields = [
  'name',
  'business',
  'amount',
  'what',
  'due',
  'date',
  'till',
];

final _field = RegExp(r'\{(\w+)\}');

/// [text] with its fields filled from [values]. A sentence whose field is
/// empty is left out; a clause set off by a comma, or a "for {x}" phrase,
/// is dropped instead when that is enough. {name} uses the first name.
String fillTemplate(String text, Map<String, String?> values) {
  String? value(String key) {
    final v = values[key]?.trim();
    if (v == null || v.isEmpty) return null;
    return key == 'name' ? v.split(RegExp(r'\s+')).first : v;
  }

  final out = StringBuffer();
  for (final m in RegExp(r'[^.!?]+[.!?]*\s*').allMatches(text)) {
    final sentence = m[0]!;
    if (_field.allMatches(sentence).every((f) => value(f[1]!) != null)) {
      out.write(sentence.replaceAllMapped(_field, (f) => value(f[1]!)!));
      continue;
    }
    final kept = _dropEmptyParts(sentence, value);
    if (kept != null) out.write(kept);
  }
  return out.toString().trim();
}

/// [sentence] without the parts whose field is empty. Null when what is
/// left still needs an empty field.
String? _dropEmptyParts(String sentence, String? Function(String) value) {
  var s = sentence.replaceAllMapped(
    RegExp(r',[^,.!?:]*\{(\w+)\}[^,.!?:]*'),
    (m) => value(m[1]!) == null ? '' : m[0]!,
  );
  s = s.replaceAllMapped(
    RegExp(r'\s+(for|from)\s+\{(\w+)\}'),
    (m) => value(m[2]!) == null ? '' : m[0]!,
  );
  if (_field.allMatches(s).any((f) => value(f[1]!) == null)) return null;
  return s.replaceAllMapped(_field, (f) => value(f[1]!)!);
}

/// What the owner set up for reminders in a business.
class ReminderSetup {
  const ReminderSetup({
    required this.templates,
    this.sendWith = SendWith.whatsapp,
    this.till,
    this.nudge = false,
    this.nudgeHour = 18,
    this.nudgeMinute = 0,
  });

  /// Starting setup in [currency].
  factory ReminderSetup.starting(String currency) =>
      ReminderSetup(templates: defaultTemplates(currency));

  static ReminderSetup fromJson(Map<String, Object?>? json, String currency) {
    if (json == null) return ReminderSetup.starting(currency);
    final list = json['templates'];
    final templates = [
      if (list is List)
        for (final t in list) ?ReminderTemplate.fromJson(t),
    ];
    final send = SendWith.values
        .where((s) => s.name == json['sendWith'])
        .firstOrNull;
    final hour = json['nudgeHour'], minute = json['nudgeMinute'];
    final till = json['till'];
    return ReminderSetup(
      templates: templates.isEmpty ? defaultTemplates(currency) : templates,
      sendWith: send ?? SendWith.whatsapp,
      till: till is String && till.trim().isNotEmpty ? till : null,
      nudge: json['nudge'] == true,
      nudgeHour: hour is int && hour >= 0 && hour < 24 ? hour : 18,
      nudgeMinute: minute is int && minute >= 0 && minute < 60 ? minute : 0,
    );
  }

  final List<ReminderTemplate> templates;

  /// The business's default; each customer can have their own.
  final SendWith sendWith;

  /// The till or Paybill reminders ask customers to pay to.
  final String? till;

  /// A daily notification of who is due, at [nudgeHour]:[nudgeMinute].
  final bool nudge;
  final int nudgeHour;
  final int nudgeMinute;

  ReminderSetup copyWith({
    List<ReminderTemplate>? templates,
    SendWith? sendWith,
    String? Function()? till,
    bool? nudge,
    int? nudgeHour,
    int? nudgeMinute,
  }) => ReminderSetup(
    templates: templates ?? this.templates,
    sendWith: sendWith ?? this.sendWith,
    till: till == null ? this.till : till(),
    nudge: nudge ?? this.nudge,
    nudgeHour: nudgeHour ?? this.nudgeHour,
    nudgeMinute: nudgeMinute ?? this.nudgeMinute,
  );

  Map<String, Object?> toJson() => {
    'templates': [for (final t in templates) t.toJson()],
    'sendWith': sendWith.name,
    'till': till,
    'nudge': nudge,
    'nudgeHour': nudgeHour,
    'nudgeMinute': nudgeMinute,
  };
}
