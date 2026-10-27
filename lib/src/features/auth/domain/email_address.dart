/// Tidies what someone typed into an email address: trimmed and lower case.
/// Returns null when it is not shaped like `name@example.com`.
///
/// A light check only; the server does the real validation.
String? normaliseEmail(String input) {
  final email = input.trim().toLowerCase();
  if (email.length > 254) return null;
  if (!RegExp(r'^[^\s@]+@([^\s@.]+\.)+[^\s@.]{2,}$').hasMatch(email)) {
    return null;
  }
  return email;
}
