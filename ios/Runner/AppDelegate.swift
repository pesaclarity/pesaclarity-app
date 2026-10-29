import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channels: [AnyObject] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets reminders show while the app is open.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PesaClarityChannels")
    else { return }
    let messenger = registrar.messenger()
    channels = [
      MessagesChannel(messenger: messenger),
      DocumentsChannel(messenger: messenger),
      ShareChannel(messenger: messenger),
      DeviceChannel(messenger: messenger),
      DeviceIntegrityChannel(messenger: messenger),
    ]
  }
}

/// The view controller on top, to present pickers and share sheets from.
func topViewController() -> UIViewController? {
  let window = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .first { $0.isKeyWindow }
  var top = window?.rootViewController
  while let presented = top?.presentedViewController {
    top = presented
  }
  return top
}
