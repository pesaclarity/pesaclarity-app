/// The friendly reminder for a customer, in the spec's starting wording:
/// "Hi {name}, a friendly reminder from {business}: KES {amount} for
/// {what}, due {due}. Thank you!". A part whose field is empty is left out.
String friendlyReminder({
  required String name,
  required String business,
  required String amount,
  String? what,
  String? due,
}) {
  final firstName = name.trim().split(RegExp(r'\s+')).first;
  final buffer = StringBuffer(
    'Hi $firstName, a friendly reminder from $business: $amount',
  );
  if (what != null && what.trim().isNotEmpty) {
    buffer.write(' for ${what.trim()}');
  }
  if (due != null && due.trim().isNotEmpty) {
    buffer.write(', due ${due.trim()}');
  }
  buffer.write('. Thank you!');
  return buffer.toString();
}
