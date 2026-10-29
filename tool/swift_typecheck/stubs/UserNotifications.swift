// Stand-in for Apple's UserNotifications on Linux, for tool/swift_typecheck only. Declares just
// what ios/Runner uses, with Apple's signatures. Never shipped.
import Foundation
public protocol UNUserNotificationCenterDelegate: NSObjectProtocol {}
open class UNUserNotificationCenter: NSObject {
  public class func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
  weak open var delegate: UNUserNotificationCenterDelegate?
}
