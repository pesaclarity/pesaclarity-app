/// Light or dark: as the phone is set, or always one of them.
enum ThemeChoice {
  system('System'),
  light('Light'),
  dark('Dark');

  const ThemeChoice(this.label);

  final String label;
}

/// How text fields are drawn across the app.
enum FieldStyle {
  underlined('Underlined'),
  boxed('Boxed');

  const FieldStyle(this.label);

  final String label;
}

/// How the app looks, the same in every space.
class LookSettings {
  const LookSettings({
    this.theme = ThemeChoice.system,
    this.fields = FieldStyle.underlined,
  });

  final ThemeChoice theme;
  final FieldStyle fields;

  LookSettings copyWith({ThemeChoice? theme, FieldStyle? fields}) =>
      LookSettings(theme: theme ?? this.theme, fields: fields ?? this.fields);

  Map<String, Object?> toJson() => {'theme': theme.name, 'fields': fields.name};

  static LookSettings fromJson(Map<String, Object?>? json) => LookSettings(
    theme:
        ThemeChoice.values.where((t) => t.name == json?['theme']).firstOrNull ??
        ThemeChoice.system,
    fields:
        FieldStyle.values.where((f) => f.name == json?['fields']).firstOrNull ??
        FieldStyle.underlined,
  );
}
