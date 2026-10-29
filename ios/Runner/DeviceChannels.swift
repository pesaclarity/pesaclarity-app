import Flutter
import UIKit

/// `com.pesaclarity.app/device`: the name shown in the signed-in phones list.
final class DeviceChannel {
  private let methods: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/device", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      // Since iOS 16 this is the model, such as "iPhone", not the owner's name.
      call.method == "name" ? result(UIDevice.current.name) : result(FlutterMethodNotImplemented)
    }
  }
}

/// `com.pesaclarity.app/device_integrity`: signs that the iPhone is
/// jailbroken, reported with the Android key names.
final class DeviceIntegrityChannel {
  private let methods: FlutterMethodChannel

  private static let jailbreakPaths = [
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/bin/bash",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/private/var/lib/apt",
    "/var/jb",
  ]

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: "com.pesaclarity.app/device_integrity", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      guard call.method == "check" else { return result(FlutterMethodNotImplemented) }
      result([
        "suBinary": Self.looksJailbroken(),
        "testKeys": false,
        "appDebuggable": Self.isDebugBuild,
      ])
    }
  }

  private static func looksJailbroken() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      if jailbreakPaths.contains(where: FileManager.default.fileExists(atPath:)) { return true }
      // Apps cannot write outside their sandbox unless it is broken.
      let probe = "/private/pesaclarity_probe.txt"
      if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
        try? FileManager.default.removeItem(atPath: probe)
        return true
      }
      return false
    #endif
  }

  private static var isDebugBuild: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }
}

/// `com.pesaclarity.app/share`: the share sheet, for loan reminders.
final class ShareChannel {
  private let methods: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/share", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      guard call.method == "shareText" else { return result(FlutterMethodNotImplemented) }
      guard let text = (call.arguments as? [String: Any])?["text"] as? String else {
        return result(FlutterError(code: "argument", message: "text is required", details: nil))
      }
      guard let top = topViewController() else {
        return result(FlutterError(code: "unavailable", message: "Nothing to share from", details: nil))
      }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = top.view
      top.present(sheet, animated: true)
      result(nil)
    }
  }
}
