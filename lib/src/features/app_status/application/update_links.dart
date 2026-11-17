import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/flavor.dart';
import '../../../config/links.dart';

/// Where this build was installed from, as app status names it: `play`,
/// `foss` (F-Droid), `ios` or `website` (the APK from the download page).
enum UpdateChannel { play, foss, ios, website }

/// Set to `website` for the APKs on the download page, so their update
/// button goes there instead of to a store.
const _distribution = String.fromEnvironment('PESACLARITY_DISTRIBUTION');

UpdateChannel updateChannelFor(
  AppFlavor flavor, {
  required String distribution,
}) {
  if (distribution == 'website') return UpdateChannel.website;
  return switch (flavor) {
    AppFlavor.play => UpdateChannel.play,
    AppFlavor.foss => UpdateChannel.foss,
    AppFlavor.appstore => UpdateChannel.ios,
  };
}

/// The page that installs a newer version for [channel]: the Play listing,
/// the F-Droid page, or the website's download page (also for iPhone, which
/// installs from there until it is in the App Store).
Uri updateUrlFor(UpdateChannel channel) => switch (channel) {
  UpdateChannel.play => Uri.https('play.google.com', '/store/apps/details', {
    'id': appPackageId,
  }),
  UpdateChannel.foss => Uri.https('f-droid.org', '/packages/$appPackageId/'),
  UpdateChannel.ios || UpdateChannel.website => Uri.parse(downloadPageUrl),
};

final updateChannelProvider = Provider<UpdateChannel>(
  (ref) => updateChannelFor(
    ref.watch(appFlavorProvider),
    distribution: _distribution,
  ),
);

/// `android` or `ios`, as app status names the platform.
final appStatusPlatformProvider = Provider<String>(
  (ref) =>
      ref.watch(updateChannelProvider) == UpdateChannel.ios ? 'ios' : 'android',
);

/// Opens the store or download page.
abstract interface class UpdateOpener {
  Future<bool> open(Uri uri);
}

class BrowserUpdateOpener implements UpdateOpener {
  const BrowserUpdateOpener();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

final updateOpenerProvider = Provider<UpdateOpener>(
  (ref) => const BrowserUpdateOpener(),
);

/// Opens where this build updates from.
Future<void> openUpdate(WidgetRef ref) async {
  try {
    await ref
        .read(updateOpenerProvider)
        .open(updateUrlFor(ref.read(updateChannelProvider)));
  } on Object {
    // Nothing to open it with: the button stays for another try.
  }
}
