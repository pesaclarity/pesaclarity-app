// Stand-in for Apple's ContactsUI, and the Contacts types it re-exports, on Linux, for
// tool/swift_typecheck only. Declares just what ios/Runner uses, with Apple's signatures.
// Never shipped.
import UIKit

public let CNContactPhoneNumbersKey: String = "phoneNumbers"

open class CNContact: NSObject {}
open class CNPhoneNumber: NSObject {
  open var stringValue: String { "" }
}
open class CNContactProperty: NSObject {
  open var contact: CNContact { CNContact() }
  open var key: String { "" }
  open var value: Any? { nil }
}
open class CNContactFormatter: NSObject {
  public enum Style: Int { case fullName, phoneticFullName }
  open class func string(from contact: CNContact, style: Style) -> String? { nil }
}

public protocol CNContactPickerDelegate: NSObjectProtocol {
  func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty)
  func contactPickerDidCancel(_ picker: CNContactPickerViewController)
}
// The delegate's methods are optional in Apple's Objective-C protocol.
extension CNContactPickerDelegate {
  public func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {}
  public func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
}
open class CNContactPickerViewController: UIViewController {
  weak open var delegate: CNContactPickerDelegate?
  open var displayedPropertyKeys: [Any]?
  open var predicateForSelectionOfProperty: NSPredicate?
}

// Apple-only Foundation API, missing from swift-corelibs-foundation.
extension NSPredicate {
  public convenience init(format predicateFormat: String) { self.init(value: true) }
}
