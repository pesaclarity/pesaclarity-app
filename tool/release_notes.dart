// Plain release notes for people, from the pull requests merged into dev
// since the last release. Run through tool/release_notes; see its usage
// below or run it with --help.
//
// Each pull request's "## Release note" section is its note (the pull
// request template asks for one). Without one, the title is made plain:
// "feat(spaces): money between spaces (decision 0027)" becomes "Money
// between spaces.". "none", and chore, ci, docs, test and build changes,
// leave no note. The rest are grouped under New (feat), Improved (perf,
// refactor, ux) and Fixed (fix).
//
// Only dart:io, so it runs with a bare Dart SDK and needs no pub get. Talks
// to GitHub through gh (GH_TOKEN), over the REST API.

import 'dart:convert';
import 'dart:io';

const usage = '''
Usage: tool/release_notes --version X.Y.Z [options]

Prints the notes for release vX.Y.Z (a dry run) unless --publish is given.

  --version X.Y.Z     the release (required)
  --to REF            last commit of the release (default: tag vX.Y.Z)
  --from TAG          the previous release (default: the highest vA.B.C
                      tag below X.Y.Z)
  --repo OWNER/NAME   default: GH_REPO or GITHUB_REPOSITORY
  --base BRANCH       branch the pull requests were merged into (dev)
  --whatsnew-dir DIR  also write Play's "What's new" text (at most 500
                      characters) to DIR/whatsnew-en-US
  --publish           rewrite the GitHub release's notes (idempotent)
''';

/// The longest "What's new" text Google Play takes.
const playLimit = 500;

/// Said when a release has nothing users would notice.
const nothingToSay = 'Small fixes and improvements.';

const _detailsOpen = '<details><summary>Full changelog</summary>';
const _detailsClose = '</details>';

class PullRequest {
  const PullRequest(this.number, this.title, this.body);

  final int number;
  final String title;
  final String body;
}

/// The groups, in the order the notes show them.
enum Group {
  added('New'),
  improved('Improved'),
  fixed('Fixed');

  const Group(this.heading);

  final String heading;
}

class ReleaseNotes {
  ReleaseNotes(this.groups);

  final Map<Group, List<String>> groups;

  bool get isEmpty => groups.values.every((lines) => lines.isEmpty);

  /// The user part of the GitHub release, in Markdown.
  String markdown(String version) {
    final out = StringBuffer('## What\'s new in v$version\n');
    if (isEmpty) {
      out.write('\n$nothingToSay\n');
    }
    for (final group in Group.values) {
      final lines = groups[group] ?? const [];
      if (lines.isEmpty) continue;
      out.write('\n### ${group.heading}\n\n');
      for (final line in lines) {
        out.write('- $line\n');
      }
    }
    return out.toString();
  }

  /// Play's "What's new": plain text, at most [limit] characters. When the
  /// notes are longer, Improved lines go first, then New, then Fixed.
  String whatsNew({int limit = playLimit}) {
    if (isEmpty) return nothingToSay;
    final kept = {for (final group in Group.values) group: <String>[]};
    for (final group in const [Group.fixed, Group.added, Group.improved]) {
      for (final line in groups[group] ?? const <String>[]) {
        kept[group]!.add(line);
        if (_plain(kept).length > limit) kept[group]!.removeLast();
      }
    }
    if (kept.values.every((lines) => lines.isEmpty)) {
      // Not even one line fits: shorten the first one.
      final group = const [
        Group.fixed,
        Group.added,
        Group.improved,
      ].firstWhere((g) => (groups[g] ?? const []).isNotEmpty);
      final room = limit - '${group.heading}\n- '.length;
      kept[group]!.add(_shorten(groups[group]!.first, room));
    }
    return _plain(kept);
  }

  static String _plain(Map<Group, List<String>> groups) => [
    for (final group in Group.values)
      if (groups[group]!.isNotEmpty)
        [
          group.heading,
          for (final line in groups[group]!) '- $line',
        ].join('\n'),
  ].join('\n\n');
}

String _shorten(String line, int room) {
  if (line.length <= room) return line;
  var cut = line.substring(0, room - 1);
  final space = cut.lastIndexOf(' ');
  if (space > room ~/ 2) cut = cut.substring(0, space);
  return '${cut.replaceFirst(RegExp(r'[\s,;:.]+$'), '')}…';
}

final _conventional = RegExp(r'^([a-zA-Z]+)(\([^)]*\))?(!)?:\s*');
final _hiddenTypes = {'chore', 'ci', 'docs', 'test', 'build'};

/// Which group a title's Conventional Commits type puts it in. Null for
/// changes users don't see, or a type that says nothing about them.
Group? groupOf(String title) {
  final match = _conventional.firstMatch(title.trim());
  switch (match?.group(1)?.toLowerCase()) {
    case 'feat':
      return Group.added;
    case 'fix':
      return Group.fixed;
    case 'perf' || 'refactor' || 'ux':
      return Group.improved;
    default:
      return null;
  }
}

bool _isHidden(String title) {
  final type = _conventional.firstMatch(title.trim())?.group(1)?.toLowerCase();
  return type != null && _hiddenTypes.contains(type);
}

/// The lines under a pull request body's "## Release note" heading: an
/// empty list for "none", null when there is no note (no section, or only
/// the template's placeholder).
List<String>? releaseNoteSection(String body) {
  final lines = const LineSplitter().convert(
    body.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ''),
  );
  final heading = RegExp(
    r'^\s*#{1,6}\s*release notes?\s*:?\s*$',
    caseSensitive: false,
  );
  final start = lines.indexWhere(heading.hasMatch);
  if (start < 0) return null;
  final section = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (RegExp(r'^\s*#{1,6}\s').hasMatch(line)) break;
    final text = line.trim();
    // A horizontal rule ends the section: footers such as the generated-by
    // line come after one.
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(text)) break;
    // Generated-by and session lines are never part of a note.
    if (RegExp(
      r'generated (by|with) \[?claude code|^https://claude\.ai/',
      caseSensitive: false,
    ).hasMatch(text)) {
      break;
    }
    // The template's "<one or two plain sentences ...>" placeholder.
    if (text.isEmpty || RegExp(r'^<[^>]*>$').hasMatch(text)) continue;
    section.add(text);
  }
  if (section.isEmpty) return null;
  final bullet = RegExp(r'^[-*+]\s+');
  final notes = <String>[];
  if (section.any(bullet.hasMatch)) {
    for (final line in section) {
      if (bullet.hasMatch(line) || notes.isEmpty) {
        notes.add(line.replaceFirst(bullet, ''));
      } else {
        notes[notes.length - 1] = '${notes.last} $line';
      }
    }
  } else {
    notes.add(section.join(' '));
  }
  return notes.where((n) => !_isNone(n)).toList();
}

bool _isNone(String note) {
  final word = note.toLowerCase().replaceAll(RegExp(r'[^a-z/]'), '');
  return word == 'none' || word == 'n/a' || word.isEmpty;
}

/// A pull request title made plain: no type or scope, decision numbers,
/// ticket references or hashes, as a sentence.
String plainTitle(String title) =>
    plainLine(title.trim().replaceFirst(_conventional, ''));

/// A note as people read it: no ticket references, hashes, decision numbers
/// or emoji, starting with a capital letter and ending with a full stop.
String plainLine(String text) {
  var line = text
      // Emoji and :shortcodes:.
      .replaceAll(
        RegExp(
          r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
          unicode: true,
        ),
        '',
      )
      .replaceAll(RegExp(r':[a-z][a-z0-9_+-]*:'), '')
      // Decision numbers: "(decision 0027)", "(0030)", "(0026 item 5)",
      // "decision 0027".
      .replaceAll(
        RegExp(
          r'\(\s*(decisions?\s+)?\d{4}(\s+items?\s+\d+)?\s*\)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\bdecisions?\s+\d{4}(\s+items?\s+\d+)?\b',
          caseSensitive: false,
        ),
        '',
      )
      // Pull request and issue references: "#12", "app#12", "owner/repo#12".
      .replaceAll(RegExp(r'\(?([\w.-]+(/[\w.-]+)?)?#\d+\b\)?'), '')
      // Tickets such as "PC-123" or "[PC-123]".
      .replaceAll(RegExp(r'\[?\b[A-Z][A-Z0-9]+-\d+\b\]?'), '')
      // Commit hashes, with or without brackets or Markdown links.
      .replaceAll(
        RegExp(
          r'\(?\[?\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b\]?(\([^)]*\))?\)?',
        ),
        '',
      )
      // What the removals leave behind.
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s+(?=[,.;:!?)])'), '')
      .replaceAll(RegExp(r'(?<=\()\s+'), '')
      .replaceAll(RegExp(r'([,;:])(?=[,;:.])'), '')
      .trim()
      .replaceFirst(RegExp(r'^[\s,;:.\-–—]+'), '')
      .replaceFirst(RegExp(r'[\s,;:\-–—]+$'), '');
  if (line.isEmpty) return line;
  line = line[0].toUpperCase() + line.substring(1);
  if (!RegExp(r'[.!?]$').hasMatch(line)) line = '$line.';
  return line;
}

String _key(String line) =>
    line.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// The notes for these pull requests, in the order given.
ReleaseNotes buildNotes(Iterable<PullRequest> prs) {
  final groups = {for (final group in Group.values) group: <String>[]};
  final seen = <String>{};
  for (final pr in prs) {
    if (_isHidden(pr.title)) continue;
    final written = releaseNoteSection(pr.body);
    // A written note on a change without a feat, fix or perf-like type
    // (a revert, say) still counts, as an improvement.
    final group =
        groupOf(pr.title) ?? (written == null ? null : Group.improved);
    if (group == null) continue;
    final lines = written?.map(plainLine) ?? [plainTitle(pr.title)];
    for (final line in lines) {
      if (line.isEmpty || !seen.add(_key(line))) continue;
      groups[group]!.add(line);
    }
  }
  return ReleaseNotes(groups);
}

/// The GitHub release's new notes: the plain notes, then the changelog it
/// had (release-please's) folded away. Built from its own output again, it
/// gives the same text, so running twice changes nothing.
String releaseBody(String version, ReleaseNotes notes, String currentBody) {
  final changelog = originalChangelog(currentBody);
  final out = StringBuffer(notes.markdown(version));
  if (changelog.isNotEmpty) {
    out.write('\n$_detailsOpen\n\n$changelog\n\n$_detailsClose\n');
  }
  return out.toString();
}

/// The changelog a release had before [releaseBody] rewrote it.
String originalChangelog(String body) {
  final normalised = body.replaceAll('\r\n', '\n');
  final open = normalised.indexOf(_detailsOpen);
  if (open < 0) return normalised.trim();
  final close = normalised.lastIndexOf(_detailsClose);
  final end = close > open ? close : normalised.length;
  return normalised.substring(open + _detailsOpen.length, end).trim();
}

/// "1.2.3" as numbers, or null for anything else (pre-releases too).
List<int>? parseVersion(String text) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// The highest release tag below [version], or null when there is none.
String? previousTag(Iterable<String> tags, String version) {
  final current = parseVersion(version)!;
  String? best;
  List<int>? bestVersion;
  for (final tag in tags) {
    if (!tag.startsWith('v')) continue;
    final v = parseVersion(tag);
    if (v == null || compareVersions(v, current) >= 0) continue;
    if (bestVersion == null || compareVersions(v, bestVersion) > 0) {
      best = tag;
      bestVersion = v;
    }
  }
  return best;
}

// GitHub, through gh.

Future<String> _gh(List<String> args) async {
  final result = await Process.run('gh', ['api', ...args]);
  if (result.exitCode != 0) {
    throw Exception(
      'gh api ${args.firstWhere((a) => !a.startsWith('-'))} failed: ${result.stderr}'
          .trim(),
    );
  }
  return result.stdout as String;
}

List<String> _lines(String text) =>
    const LineSplitter().convert(text).where((l) => l.isNotEmpty).toList();

Future<List<PullRequest>> mergedPullRequests(
  String repo,
  String from,
  String to,
  String base,
) async {
  final shas = _lines(
    await _gh([
      '--paginate',
      'repos/$repo/compare/$from...$to?per_page=100',
      '--jq',
      '.commits[].sha',
    ]),
  );
  final found = <int, PullRequest>{};
  // A few at a time: one request per commit.
  for (var i = 0; i < shas.length; i += 8) {
    final pages = await Future.wait([
      for (final sha in shas.skip(i).take(8))
        _gh(['repos/$repo/commits/$sha/pulls?per_page=100']),
    ]);
    for (final page in pages) {
      for (final pr
          in (jsonDecode(page) as List).cast<Map<String, Object?>>()) {
        final baseRef = (pr['base']! as Map<String, Object?>)['ref'];
        if (baseRef != base || pr['merged_at'] == null) continue;
        final number = pr['number']! as int;
        found[number] = PullRequest(
          number,
          pr['title']! as String,
          (pr['body'] as String?) ?? '',
        );
      }
    }
  }
  return found.values.toList()..sort((a, b) => a.number.compareTo(b.number));
}

/// The release to start from: the highest tag below [tag]. When [tag]
/// already exists and [to] is a later commit (a build by hand on a branch
/// whose pubspec.yaml still names the last release), that tag instead, so
/// the notes cover what came after it.
Future<String?> _defaultFrom(String repo, String tag, String to) async {
  final tags = <String, String>{};
  for (final line in _lines(
    await _gh([
      '--paginate',
      'repos/$repo/tags?per_page=100',
      '--jq',
      r'.[] | "\(.name) \(.commit.sha)"',
    ]),
  )) {
    final parts = line.split(' ');
    tags[parts.first] = parts.last;
  }
  final tagSha = tags[tag];
  if (tagSha != null && to != tag) {
    final toSha = (await _gh(['repos/$repo/commits/$to', '--jq', '.sha']))
        .trim();
    if (toSha != tagSha) return tag;
  }
  return previousTag(tags.keys, tag.substring(1));
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.write(usage);
      return;
    }
    if (arg == '--publish') {
      flags.add(arg);
    } else if (arg.startsWith('--') && i + 1 < args.length) {
      options[arg] = args[++i];
    } else {
      stderr.write('Unknown option: $arg\n\n$usage');
      exit(2);
    }
  }
  final version = options['--version'];
  if (version == null || parseVersion(version) == null) {
    stderr.write('Give the release as --version X.Y.Z.\n\n$usage');
    exit(2);
  }
  final env = Platform.environment;
  final repo = options['--repo'] ?? env['GH_REPO'] ?? env['GITHUB_REPOSITORY'];
  if (repo == null || repo.isEmpty) {
    stderr.write('Give the repository as --repo OWNER/NAME or GH_REPO.\n');
    exit(2);
  }
  final tag = 'v$version';
  final to = options['--to'] ?? tag;
  final from = options['--from'] ?? await _defaultFrom(repo, tag, to);
  if (from == null) {
    stderr.write('No release before $tag; give one with --from.\n');
    exit(1);
  }

  final prs = await mergedPullRequests(
    repo,
    from,
    to,
    options['--base'] ?? 'dev',
  );
  stderr.writeln(
    'Release $tag: ${prs.length} pull requests merged since $from'
    '${prs.isEmpty ? '' : ' (${prs.map((p) => '#${p.number}').join(', ')})'}.',
  );
  final notes = buildNotes(prs);
  final whatsNew = notes.whatsNew();

  final dir = options['--whatsnew-dir'];
  if (dir != null) {
    final file = File('$dir/whatsnew-en-US');
    await file.parent.create(recursive: true);
    await file.writeAsString('$whatsNew\n');
    stderr.writeln('Wrote ${file.path} (${whatsNew.length} characters).');
  }

  if (!flags.contains('--publish')) {
    // A dry run: what the release's notes would become, read only.
    Map<String, Object?>? release;
    try {
      release = jsonDecode(
        await _gh(['repos/$repo/releases/tags/$tag']),
      ) as Map<String, Object?>;
    } on Exception {
      stderr.writeln('No release $tag yet; showing the notes alone.');
    }
    stdout
      ..writeln(
        release == null
            ? notes.markdown(version)
            : releaseBody(version, notes, (release['body'] as String?) ?? ''),
      )
      ..writeln(
        '--- Google Play, what\'s new (${whatsNew.length} characters) ---',
      )
      ..writeln(whatsNew);
    return;
  }

  final release = jsonDecode(
    await _gh(['repos/$repo/releases/tags/$tag']),
  ) as Map<String, Object?>;
  final current = (release['body'] as String?) ?? '';
  final body = releaseBody(version, notes, current);
  if (body.trim() == current.replaceAll('\r\n', '\n').trim()) {
    stderr.writeln('The notes of $tag are already up to date.');
    return;
  }
  final input = File(
    '${Directory.systemTemp.createTempSync('notes').path}/body.json',
  );
  await input.writeAsString(jsonEncode({'body': body}));
  await _gh([
    '--method',
    'PATCH',
    'repos/$repo/releases/${release['id']}',
    '--input',
    input.path,
    '--jq',
    '.html_url',
  ]);
  stderr.writeln('Rewrote the notes of $tag.');
}
