/// Web pages the app points people to. Override at build time with
/// --dart-define when the site moves.
library;

/// How to install through Obtainium, for phones (Xiaomi, Redmi, POCO) that
/// never offer "Allow restricted settings" for an app installed from a file.
const installGuideUrl = String.fromEnvironment(
  'PESACLARITY_INSTALL_GUIDE_URL',
  defaultValue: 'https://pesaclarity.github.io/install/#xiaomi',
);
