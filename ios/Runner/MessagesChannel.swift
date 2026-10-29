import Flutter
import UIKit

/// The `com.pesaclarity.app/sms` channel on iPhone. iOS has no inbox apps
/// can read, so messages come from the Shortcuts automation through
/// [MessageQueue]. The method names match the Android channel.
final class MessagesChannel: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/sms", binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: "com.pesaclarity.app/sms/incoming", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    events.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    // Nothing to grant: the person chooses what the automation sends.
    case "access", "requestAccess":
      result("granted")
    case "openSettings":
      openShortcuts()
      result(nil)
    case "openShortcuts":
      openShortcuts()
      result(nil)
    case "readInbox":
      let senders = args["senders"] as? [String] ?? []
      let since = (args["sinceMillis"] as? NSNumber)?.int64Value ?? 0
      DispatchQueue.global(qos: .userInitiated).async {
        let rows = MessageQueue.shared.messages(senders: senders, sinceMillis: since).map(\.asMap)
        DispatchQueue.main.async { result(rows) }
      }
    case "release":
      let before = (args["beforeMillis"] as? NSNumber)?.int64Value ?? 0
      do {
        try MessageQueue.shared.release(beforeMillis: before)
        result(nil)
      } catch {
        result(FlutterError(code: "io_failed", message: error.localizedDescription, details: nil))
      }
    case "lastArrival":
      result(MessageQueue.shared.lastArrivalMillis.map { NSNumber(value: $0) })
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openShortcuts() {
    guard let url = URL(string: "shortcuts://") else { return }
    UIApplication.shared.open(url)
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    let watched = Set((arguments as? [String] ?? []).map(MessageQueue.normalise))
    observer = NotificationCenter.default.addObserver(
      forName: MessageQueue.didAppend, object: nil, queue: .main
    ) { note in
      guard let message = note.userInfo?["message"] as? MessageQueue.Message,
        watched.contains(MessageQueue.normalise(message.sender))
      else { return }
      eventSink(message.asMap)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    return nil
  }
}
