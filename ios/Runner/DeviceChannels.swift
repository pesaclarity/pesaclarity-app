import ContactsUI
import Flutter
import UIKit

/// `com.pesaclarity.app/device`: the name shown in the signed-in phones list,
/// and whether the iPhone is charging, so on-phone learning runs only then.
final class DeviceChannel {
  private let methods: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/device", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      switch call.method {
      case "name":
        // Since iOS 16 this is the model, such as "iPhone", not the owner's name.
        result(UIDevice.current.name)
      case "charging":
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let state = device.batteryState
        result(state == .charging || state == .full)
      default:
        result(FlutterMethodNotImplemented)
      }
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

/// `com.pesaclarity.app/share`: the share sheet, for reminders, and the
/// system contact picker for one phone number. The picker needs no contacts
/// permission and hands back only the contact chosen.
final class ShareChannel: NSObject, CNContactPickerDelegate {
  private let methods: FlutterMethodChannel
  private var pendingPick: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/share", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "shareText":
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
      case "pickPhone":
        guard let self, let top = topViewController() else {
          return result(FlutterError(code: "unavailable", message: "No contact picker", details: nil))
        }
        self.pendingPick?(nil)
        self.pendingPick = result
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        top.present(picker, animated: true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
    let number = (property.value as? CNPhoneNumber)?.stringValue
    let name = CNContactFormatter.string(from: property.contact, style: .fullName)
    pendingPick?(number == nil ? nil : ["number": number!, "name": name ?? ""])
    pendingPick = nil
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
  }
}
