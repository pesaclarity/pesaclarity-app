// Stand-in for Apple's Flutter on Linux, for tool/swift_typecheck only. Declares just
// what ios/Runner uses, with Apple's signatures. Never shipped.
@_exported import UIKit
import UserNotifications

public typealias FlutterResult = (Any?) -> Void
public typealias FlutterEventSink = (Any?) -> Void
public typealias FlutterMethodCallHandler = (FlutterMethodCall, @escaping FlutterResult) -> Void
public let FlutterMethodNotImplemented: NSObject = NSObject()

public protocol FlutterBinaryMessenger: NSObjectProtocol {}
open class FlutterMethodCall: NSObject {
  public var method: String { "" }
  public var arguments: Any? { nil }
}
open class FlutterError: NSObject {
  public init(code: String, message: String?, details: Any?) { super.init() }
}
open class FlutterMethodChannel: NSObject {
  public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger & NSObjectProtocol) { super.init() }
  open func setMethodCallHandler(_ handler: FlutterMethodCallHandler?) {}
}
public protocol FlutterStreamHandler: NSObjectProtocol {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
  func onCancel(withArguments arguments: Any?) -> FlutterError?
}
open class FlutterEventChannel: NSObject {
  public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger & NSObjectProtocol) { super.init() }
  open func setStreamHandler(_ handler: (FlutterStreamHandler & NSObjectProtocol)?) {}
}
public protocol FlutterPluginRegistrar: NSObjectProtocol {
  func messenger() -> FlutterBinaryMessenger & NSObjectProtocol
}
public protocol FlutterPluginRegistry: NSObjectProtocol {
  func registrar(forPlugin pluginKey: String) -> FlutterPluginRegistrar?
}
public protocol FlutterImplicitEngineBridge: NSObjectProtocol {
  var pluginRegistry: FlutterPluginRegistry { get }
}
public protocol FlutterImplicitEngineDelegate: NSObjectProtocol {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge)
}
open class FlutterAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  open func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
}
open class FlutterSceneDelegate: UIResponder {}
open class GeneratedPluginRegistrant: NSObject {
  public class func register(with registry: FlutterPluginRegistry) {}
}
