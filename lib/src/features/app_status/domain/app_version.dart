/// A version such as `0.3.0` or `0.4.0-dev.31`, ordered the SemVer way: a
/// pre-release comes before its release, and build metadata (`+7`) is
/// ignored.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch, this.pre);

  final int major;
  final int minor;
  final int patch;

  /// Pre-release identifiers, such as `['dev', '31']`; empty for a release.
  final List<String> pre;

  static final _pattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// The version in [text], or null when it is not one.
  static AppVersion? tryParse(String text) {
    final value = text.trim();
    if (value.length > 64) return null;
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    return AppVersion._(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4] == null ? const [] : match[4]!.split('.'),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      // A release sorts after any of its pre-releases.
      return (pre.isEmpty ? 1 : 0) - (other.pre.isEmpty ? 1 : 0);
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final order = _compareIdentifier(pre[i], other.pre[i]);
      if (order != 0) return order;
    }
    return pre.length.compareTo(other.pre.length);
  }

  static int _compareIdentifier(String a, String b) {
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    // Numbers sort before words.
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(pre));

  @override
  String toString() =>
      '$major.$minor.$patch${pre.isEmpty ? '' : '-${pre.join('.')}'}';
}
