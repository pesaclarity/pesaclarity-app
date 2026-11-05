/// How a receipt is sent: a picture sized for WhatsApp, a PDF, or plain
/// text for SMS.
enum ReceiptFormat {
  picture('Picture'),
  pdf('PDF'),
  text('Text');

  const ReceiptFormat(this.label);

  final String label;
}

/// The business's details and choices for its receipts and invoices.
class DocumentSettings {
  const DocumentSettings({
    this.business,
    this.place,
    this.phone,
    this.email,
    this.till,
    this.bank,
    this.kraPin,
    this.showKraPin = false,
    this.prefix,
    this.nextReceipt = 1,
    this.nextInvoice = 1,
    this.footer = 'Thank you, come again!',
    this.offerReceipt = true,
    this.sendAs = ReceiptFormat.picture,
  });

  /// Defaults to the space's name.
  final String? business;
  final String? place;
  final String? phone;
  final String? email;

  /// Till or Paybill, such as `Till 000000` or `Paybill 000000 account 123`.
  final String? till;

  /// Bank details for invoices.
  final String? bank;
  final String? kraPin;
  final bool showKraPin;

  /// Before each number, such as `VS-`; defaults to the initials.
  final String? prefix;
  final int nextReceipt;
  final int nextInvoice;
  final String footer;
  final bool offerReceipt;
  final ReceiptFormat sendAs;

  /// The business's name: its own, else [space].
  String nameOr(String space) => business ?? space;

  /// `VS` for Vegetable stall.
  static String initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp('[A-Za-z0-9]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return 'B';
    final letters = words.length == 1
        ? words.single.substring(0, words.single.length < 2 ? 1 : 2)
        : '${words[0][0]}${words[1][0]}';
    return letters.toUpperCase();
  }

  String prefixFor(String space) => prefix ?? '${initials(nameOr(space))}-';

  /// `VS-000246`.
  String numberLabel(String space, int number) =>
      '${prefixFor(space)}${number.toString().padLeft(6, '0')}';

  /// `AC-INV-0018`.
  String invoiceLabel(String space, int number) =>
      '${prefixFor(space)}INV-${number.toString().padLeft(4, '0')}';

  /// How to pay, on one line: `Till 000000 · Equity Bank`.
  String? get payLine {
    final parts = [?till, ?bank].where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  DocumentSettings copyWith({
    String? Function()? business,
    String? Function()? place,
    String? Function()? phone,
    String? Function()? email,
    String? Function()? till,
    String? Function()? bank,
    String? Function()? kraPin,
    bool? showKraPin,
    String? Function()? prefix,
    int? nextReceipt,
    int? nextInvoice,
    String? footer,
    bool? offerReceipt,
    ReceiptFormat? sendAs,
  }) => DocumentSettings(
    business: business == null ? this.business : business(),
    place: place == null ? this.place : place(),
    phone: phone == null ? this.phone : phone(),
    email: email == null ? this.email : email(),
    till: till == null ? this.till : till(),
    bank: bank == null ? this.bank : bank(),
    kraPin: kraPin == null ? this.kraPin : kraPin(),
    showKraPin: showKraPin ?? this.showKraPin,
    prefix: prefix == null ? this.prefix : prefix(),
    nextReceipt: nextReceipt ?? this.nextReceipt,
    nextInvoice: nextInvoice ?? this.nextInvoice,
    footer: footer ?? this.footer,
    offerReceipt: offerReceipt ?? this.offerReceipt,
    sendAs: sendAs ?? this.sendAs,
  );

  Map<String, Object?> toJson() => {
    'business': ?business,
    'place': ?place,
    'phone': ?phone,
    'email': ?email,
    'till': ?till,
    'bank': ?bank,
    'kraPin': ?kraPin,
    'showKraPin': showKraPin,
    'prefix': ?prefix,
    'nextReceipt': nextReceipt,
    'nextInvoice': nextInvoice,
    'footer': footer,
    'offerReceipt': offerReceipt,
    'sendAs': sendAs.name,
  };

  static DocumentSettings fromJson(Map<String, Object?>? json) {
    if (json == null) return const DocumentSettings();
    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    int whole(String key, int fallback) {
      final v = json[key];
      return v is num && v >= 1 ? v.toInt() : fallback;
    }

    final footer = json['footer'];
    return DocumentSettings(
      business: text('business'),
      place: text('place'),
      phone: text('phone'),
      email: text('email'),
      till: text('till'),
      bank: text('bank'),
      kraPin: text('kraPin'),
      showKraPin: json['showKraPin'] == true,
      prefix: text('prefix'),
      nextReceipt: whole('nextReceipt', 1),
      nextInvoice: whole('nextInvoice', 1),
      footer: footer is String ? footer.trim() : 'Thank you, come again!',
      offerReceipt: json['offerReceipt'] != false,
      sendAs:
          ReceiptFormat.values
              .where((f) => f.name == json['sendAs'])
              .firstOrNull ??
          ReceiptFormat.picture,
    );
  }
}
