import 'app_version.dart';

/// What a notice is: an update to install, or news from the team.
enum AppNoticeKind { update, info }

/// The one reason that may block the app: a bug that makes amounts wrong.
const amountsWrongReason = 'amounts_wrong';

/// A notice from the server, after its signature was checked.
class AppNotice {
  const AppNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.latestVersion,
    this.minVersion,
    this.requiredReason,
    this.rereadFrom,
  });

  final String id;
  final AppNoticeKind kind;
  final String title;
  final String body;
  final AppVersion? latestVersion;
  final AppVersion? minVersion;
  final String? requiredReason;

  /// Asks the app to read its messages again from this day.
  final DateTime? rereadFrom;

  /// Whether this build must update before it can be used: it is older than
  /// [minVersion], and the reason is a bug that makes amounts wrong. Any
  /// other notice with a minimum shows as the usual card.
  bool blocks(AppVersion current) =>
      kind == AppNoticeKind.update &&
      requiredReason == amountsWrongReason &&
      minVersion != null &&
      current < minVersion!;

  /// What closing the card remembers. An update is closed for its version,
  /// so the card comes back when a newer one is out.
  String get dismissKey => kind == AppNoticeKind.update
      ? 'update:${latestVersion ?? id}'
      : 'info:$id';

  /// Reads one notice, or returns null when it is malformed.
  static AppNotice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final kind = switch (json['kind']) {
      'update' => AppNoticeKind.update,
      'info' => AppNoticeKind.info,
      _ => null,
    };
    final title = json['title'];
    final body = json['body'];
    if (id is! String || kind == null || title is! String || body is! String) {
      return null;
    }
    AppVersion? version(String key) => switch (json[key]) {
      final String text => AppVersion.tryParse(text),
      _ => null,
    };
    final latest = version('latest_version');
    if (kind == AppNoticeKind.update && latest == null) return null;
    final reread = json['reread_from'];
    final reason = json['required_reason'];
    return AppNotice(
      id: id,
      kind: kind,
      title: title,
      body: body,
      latestVersion: latest,
      minVersion: version('min_version'),
      requiredReason: reason is String ? reason : null,
      rereadFrom: reread is String ? DateTime.tryParse(reread) : null,
    );
  }
}

/// The verified answer from `GET /v1/app-status` for this build.
class AppStatus {
  const AppStatus({
    required this.issuedAt,
    required this.current,
    required this.notices,
    this.latestVersion,
  });

  final DateTime issuedAt;

  /// The version this build runs.
  final AppVersion current;
  final AppVersion? latestVersion;
  final List<AppNotice> notices;

  /// The notice that blocks this build, if any.
  AppNotice? get blocking {
    for (final notice in notices) {
      if (notice.blocks(current)) return notice;
    }
    return null;
  }

  /// The cards for Home, leaving out [dismissed] ones: the newest update
  /// this build does not have yet, then the news.
  List<AppNotice> cards(Set<String> dismissed) {
    AppNotice? update;
    final news = <AppNotice>[];
    for (final notice in notices) {
      if (dismissed.contains(notice.dismissKey)) continue;
      switch (notice.kind) {
        case AppNoticeKind.update:
          final version = notice.latestVersion!;
          if (!(current < version)) continue;
          if (update == null || version > update.latestVersion!) {
            update = notice;
          }
        case AppNoticeKind.info:
          news.add(notice);
      }
    }
    return [?update, ...news];
  }
}
