import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Allows or blocks screenshots and screen recording of the app.
abstract interface class ScreenCaptureBlocker {
  /// Allows them when [allowed] and blocks them otherwise, at once. True
  /// once the phone has done so.
  Future<bool> setAllowed(bool allowed);
}

/// Asks the Android side over a method channel (`ScreenCaptureChannel.kt`),
/// which clears or sets `FLAG_SECURE` on the app's window. The window starts
/// blocked (`MainActivity.kt`), so a call that fails leaves it as it was.
class MethodChannelScreenCaptureBlocker implements ScreenCaptureBlocker {
  const MethodChannelScreenCaptureBlocker({
    this.channel = const MethodChannel('com.pesaclarity.app/screen_capture'),
  });

  final MethodChannel channel;

  @override
  Future<bool> setAllowed(bool allowed) async {
    try {
      await channel.invokeMethod<void>(allowed ? 'allow' : 'block');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final screenCaptureBlockerProvider = Provider<ScreenCaptureBlocker>(
  (ref) => const MethodChannelScreenCaptureBlocker(),
);

/// Whether the app can block screenshots on this phone, and so offers the
/// setting. Android lets an app block them; iOS does not.
final canBlockScreenCaptureProvider = Provider<bool>(
  (ref) => defaultTargetPlatform == TargetPlatform.android,
);
