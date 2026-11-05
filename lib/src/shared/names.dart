/// `NAIVAS JUJA` from a message becomes `Naivas Juja`.
String titleCase(String? raw) {
  if (raw == null) return '';
  return raw
      .trim()
      .split(RegExp(r'\s+'))
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}
