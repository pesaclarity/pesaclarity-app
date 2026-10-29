import DeviceCheck
import Flutter

/// `com.pesaclarity.app/app_attest`: Apple App Attest, so the vault can tell
/// uploads come from the genuine app. Data crosses the channel as base64.
final class AppAttestChannel {
  private let methods: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: "com.pesaclarity.app/app_attest", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in Self.handle(call, result) }
  }

  private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let service = DCAppAttestService.shared
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isSupported":
      result(service.isSupported)
    case "generateKey":
      service.generateKey { keyId, error in
        reply(result, keyId, error)
      }
    case "attestKey":
      guard let keyId = args["keyId"] as? String, let hash = data(args["clientDataHash"]) else {
        return result(FlutterError(code: "bad_args", message: "keyId and clientDataHash", details: nil))
      }
      service.attestKey(keyId, clientDataHash: hash) { attestation, error in
        reply(result, attestation?.base64EncodedString(), error)
      }
    case "generateAssertion":
      guard let keyId = args["keyId"] as? String, let hash = data(args["clientDataHash"]) else {
        return result(FlutterError(code: "bad_args", message: "keyId and clientDataHash", details: nil))
      }
      service.generateAssertion(keyId, clientDataHash: hash) { assertion, error in
        reply(result, assertion?.base64EncodedString(), error)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func data(_ value: Any?) -> Data? {
    (value as? String).flatMap { Data(base64Encoded: $0) }
  }

  private static func reply(_ result: @escaping FlutterResult, _ value: String?, _ error: Error?) {
    DispatchQueue.main.async {
      if let value {
        result(value)
        return
      }
      // invalidKey: Apple no longer knows the key; Dart registers a new one.
      let code =
        (error as? DCError)?.code == .invalidKey ? "invalid_key" : "failed"
      result(FlutterError(code: code, message: error?.localizedDescription, details: nil))
    }
  }
}
