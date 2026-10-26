import '../time/calendar.dart';

/// A policy version such as `1.0` or `1.2`, compared part by part.
class PolicyVersion implements Comparable<PolicyVersion> {
  PolicyVersion._(this.parts);

  /// Parses dotted whole numbers; throws [FormatException] otherwise.
  factory PolicyVersion.parse(String text) {
    final pieces = text.trim().split('.');
    final parts = [
      for (final piece in pieces)
        int.tryParse(piece) ??
            (throw FormatException('Not a policy version', text)),
    ];
    if (parts.any((p) => p < 0)) {
      throw FormatException('Not a policy version', text);
    }
    return PolicyVersion._(List.unmodifiable(parts));
  }

  final List<int> parts;

  bool isNewerThan(PolicyVersion other) => compareTo(other) > 0;

  @override
  int compareTo(PolicyVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is PolicyVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(_trimmed);

  List<int> get _trimmed {
    var end = parts.length;
    while (end > 1 && parts[end - 1] == 0) {
      end--;
    }
    return parts.sublist(0, end);
  }

  @override
  String toString() => parts.join('.');
}

/// What changed in one version of the policy, in plain words.
class PolicyChange {
  const PolicyChange({
    required this.version,
    required this.date,
    required this.items,
  });

  final PolicyVersion version;
  final CalendarDate date;
  final List<String> items;
}

enum PolicyBlockType { heading, paragraph, bullet, term }

/// One block of the policy text.
class PolicyBlock {
  const PolicyBlock(this.type, this.text);

  final PolicyBlockType type;
  final String text;
}

/// The privacy policy bundled with the app: its version, date, text and the
/// changes made in each version.
class PrivacyPolicy {
  const PrivacyPolicy({
    required this.title,
    required this.version,
    required this.updated,
    required this.blocks,
    this.changes = const [],
  });

  /// Builds the policy from the bundled files: [metadata] (decoded JSON with
  /// `version`, `updated` and `changes`) and [markdown], the text.
  ///
  /// The text uses a small Markdown subset: `# title`, `## heading`,
  /// `- bullet`, `**term**` on its own line, and paragraphs separated by
  /// blank lines.
  factory PrivacyPolicy.fromAssets({
    required Map<String, Object?> metadata,
    required String markdown,
  }) {
    final blocks = <PolicyBlock>[];
    var title = 'Privacy policy';
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(PolicyBlock(PolicyBlockType.paragraph, paragraph.join(' ')));
      paragraph.clear();
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('## ')) {
        flush();
        blocks.add(PolicyBlock(PolicyBlockType.heading, line.substring(3)));
      } else if (line.startsWith('# ')) {
        flush();
        title = line.substring(2);
      } else if (line.startsWith('- ')) {
        flush();
        blocks.add(PolicyBlock(PolicyBlockType.bullet, line.substring(2)));
      } else if (line.startsWith('**') &&
          line.endsWith('**') &&
          line.length > 4) {
        flush();
        blocks.add(
          PolicyBlock(PolicyBlockType.term, line.substring(2, line.length - 2)),
        );
      } else {
        paragraph.add(line);
      }
    }
    flush();

    final changes = <PolicyChange>[
      for (final change in (metadata['changes'] as List? ?? const []))
        if (change is Map)
          PolicyChange(
            version: PolicyVersion.parse(change['version'] as String),
            date: _parseDate(change['date'] as String),
            items: [for (final item in change['items'] as List) '$item'],
          ),
    ]..sort((a, b) => b.version.compareTo(a.version));

    return PrivacyPolicy(
      title: title,
      version: PolicyVersion.parse(metadata['version'] as String),
      updated: _parseDate(metadata['updated'] as String),
      blocks: List.unmodifiable(blocks),
      changes: List.unmodifiable(changes),
    );
  }

  final String title;
  final PolicyVersion version;
  final CalendarDate updated;
  final List<PolicyBlock> blocks;

  /// Newest first.
  final List<PolicyChange> changes;

  /// Changes made after [accepted], newest first.
  List<PolicyChange> changesSince(PolicyVersion accepted) => [
    for (final change in changes)
      if (change.version.isNewerThan(accepted) &&
          !change.version.isNewerThan(version))
        change,
  ];

  /// The version line under the policy, such as
  /// `Version 1.0 · updated 26 Oct 2026`.
  String get versionLine =>
      'Version $version · updated ${formatPolicyDate(updated)}';

  /// The whole policy as plain text, for sending by email.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln('Version $version, updated ${formatPolicyDate(updated)}');
    for (final block in blocks) {
      switch (block.type) {
        case PolicyBlockType.heading:
          buffer
            ..writeln()
            ..writeln(block.text.toUpperCase());
        case PolicyBlockType.paragraph:
          buffer
            ..writeln()
            ..writeln(block.text);
        case PolicyBlockType.bullet:
          buffer.writeln('- ${block.text}');
        case PolicyBlockType.term:
          buffer
            ..writeln()
            ..writeln('${block.text}:');
      }
    }
    return buffer.toString().trimRight();
  }
}

CalendarDate _parseDate(String iso) {
  final parsed = DateTime.parse(iso);
  return CalendarDate(parsed.year, parsed.month, parsed.day);
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A policy date such as `26 Oct 2026`.
String formatPolicyDate(CalendarDate date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
