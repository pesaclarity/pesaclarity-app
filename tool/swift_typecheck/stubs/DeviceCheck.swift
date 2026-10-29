// Stand-in for Apple's DeviceCheck on Linux, for tool/swift_typecheck only. Declares just
// what ios/Runner uses, with Apple's signatures. Never shipped.
import Foundation
open class DCAppAttestService: NSObject {
  public class var shared: DCAppAttestService { DCAppAttestService() }
  public var isSupported: Bool { false }
  open func generateKey(completionHandler: @escaping (String?, Error?) -> Void) {}
  open func attestKey(_ keyId: String, clientDataHash: Data, completionHandler: @escaping (Data?, Error?) -> Void) {}
  open func generateAssertion(_ keyId: String, clientDataHash: Data, completionHandler: @escaping (Data?, Error?) -> Void) {}
}
public struct DCError: Error {
  public enum Code: Int { case unknownSystemFailure, featureUnsupported, invalidInput, invalidKey, serverUnavailable }
  public var code: Code
}
