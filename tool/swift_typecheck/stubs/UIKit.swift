// Stand-in for Apple's UIKit on Linux, for tool/swift_typecheck only. Declares just
// what ios/Runner uses, with Apple's signatures. Never shipped.
@_exported import Foundation

open class UIResponder: NSObject {}
public protocol UIApplicationDelegate: AnyObject {}
extension UIApplicationDelegate { public static func main() {} }

open class UIScene: UIResponder {}
open class UIWindowScene: UIScene { public var windows: [UIWindow] { [] } }
open class UIView: UIResponder {}
open class UIWindow: UIView {
  public var isKeyWindow: Bool { false }
  public var rootViewController: UIViewController?
}
open class UIViewController: UIResponder {
  public var view: UIView! { nil }
  public var presentedViewController: UIViewController? { nil }
  public var popoverPresentationController: UIPopoverPresentationController? { nil }
  open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {}
}
open class UIPopoverPresentationController: NSObject { public var sourceView: UIView? }

open class UIApplication: UIResponder {
  public struct LaunchOptionsKey: Hashable, RawRepresentable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
  }
  public struct OpenExternalURLOptionsKey: Hashable, RawRepresentable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
  }
  public class var shared: UIApplication { UIApplication() }
  public var connectedScenes: Set<UIScene> { [] }
  open func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {}
}

open class UIDevice: NSObject {
  public class var current: UIDevice { UIDevice() }
  public var name: String { "" }
}

open class UIActivity: NSObject {}
open class UIActivityViewController: UIViewController {
  public init(activityItems: [Any], applicationActivities: [UIActivity]?) { super.init() }
}

public protocol UIDocumentPickerDelegate: NSObjectProtocol {}
open class UIDocumentPickerViewController: UIViewController {
  weak open var delegate: UIDocumentPickerDelegate?
  open var allowsMultipleSelection: Bool = false
  public init(forOpeningContentTypes contentTypes: [UTTypeStub], asCopy: Bool) { super.init() }
  public convenience init(forOpeningContentTypes contentTypes: [UTTypeStub]) { self.init(forOpeningContentTypes: contentTypes, asCopy: false) }
  public init(forExporting urls: [URL], asCopy: Bool) { super.init() }
}
// Lets UniformTypeIdentifiers' UTType be used here without a module cycle.
public struct UTTypeStub: Hashable {
  public static let folder = UTTypeStub()
  public static let item = UTTypeStub()
}

// Apple-only Foundation API, missing from swift-corelibs-foundation.
extension URL {
  public func startAccessingSecurityScopedResource() -> Bool { true }
  public func stopAccessingSecurityScopedResource() {}
}
extension URL {
  public struct BookmarkCreationOptionsStub: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
  }
  public func bookmarkData(options: BookmarkCreationOptionsStub = [], includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil, relativeTo url: URL? = nil) throws -> Data { Data() }
  public init(resolvingBookmarkData data: Data, options: BookmarkCreationOptionsStub = [], relativeTo url: URL? = nil, bookmarkDataIsStale: inout Bool) throws { self.init(fileURLWithPath: "/") }
}
