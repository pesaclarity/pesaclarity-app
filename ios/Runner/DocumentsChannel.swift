import Flutter
import UIKit
import UniformTypeIdentifiers

/// `com.pesaclarity.app/documents` on iPhone: backups go to a folder the
/// person picks in Files (on the iPhone, iCloud Drive or another provider),
/// restores open a single file, and "save as" exports the recovery key.
///
/// A picked folder is kept as a bookmark, sent to Dart as
/// "bookmark:<base64>". A file listed in it is "bookmark:<base64>#<name>".
final class DocumentsChannel: NSObject, UIDocumentPickerDelegate {
  private static let bookmarkScheme = "bookmark:"

  private enum Request { case folder, file, saveAs(temp: URL) }

  private let methods: FlutterMethodChannel
  private var pending: (request: Request, result: FlutterResult)?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "com.pesaclarity.app/documents", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pickFolder":
      present(
        UIDocumentPickerViewController(forOpeningContentTypes: [.folder]), .folder, result)
    case "pickFile":
      present(
        UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true), .file,
        result)
    case "saveAs":
      guard let source = args["source"] as? String, let name = args["name"] as? String else {
        return result(FlutterError(code: "bad_args", message: "source and name are required", details: nil))
      }
      do {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: temp)
        present(
          UIDocumentPickerViewController(forExporting: [temp], asCopy: true), .saveAs(temp: temp),
          result)
      } catch {
        result(FlutterError(code: "io_failed", message: error.localizedDescription, details: nil))
      }
    case "canWrite":
      result((args["uri"] as? String).flatMap(Self.folderURL) != nil)
    case "writeFile":
      background(result) {
        let folder = try Self.requireFolder(args["treeUri"] as? String)
        let name = args["name"] as? String ?? ""
        let source = URL(fileURLWithPath: args["source"] as? String ?? "")
        try Self.accessing(folder) {
          let target = folder.appendingPathComponent(name)
          if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
          }
          try FileManager.default.copyItem(at: source, to: target)
        }
        return nil
      }
    case "listFiles":
      background(result) {
        let tree = args["treeUri"] as? String ?? ""
        let folder = try Self.requireFolder(tree)
        return try Self.accessing(folder) {
          let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
          let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
          return urls.compactMap { url -> [String: Any?]? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { return nil }
            let modified = values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            return [
              "uri": "\(tree)#\(url.lastPathComponent)",
              "name": url.lastPathComponent,
              "size": values?.fileSize,
              "modifiedMillis": modified,
            ]
          }
        }
      }
    case "copyToFile":
      background(result) {
        let uri = args["uri"] as? String ?? ""
        let destination = URL(fileURLWithPath: args["destination"] as? String ?? "")
        try Self.copy(uri, to: destination)
        return nil
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Pickers

  private func present(
    _ picker: UIDocumentPickerViewController, _ request: Request, _ result: @escaping FlutterResult
  ) {
    guard pending == nil else {
      return result(FlutterError(code: "busy", message: "A picker is already showing", details: nil))
    }
    guard let top = topViewController() else {
      return result(FlutterError(code: "unavailable", message: "Nothing to show the picker from", details: nil))
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pending = (request, result)
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let taken = takePending() else { return }
    let (request, result) = taken
    guard let url = urls.first else { return result(nil) }
    switch request {
    case .folder:
      do {
        let bookmark = try Self.accessing(url) { try url.bookmarkData() }
        result(["uri": Self.bookmarkScheme + bookmark.base64EncodedString(), "name": url.lastPathComponent])
      } catch {
        result(FlutterError(code: "no_access", message: error.localizedDescription, details: nil))
      }
    case .file:
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
      result(["uri": url.absoluteString, "name": url.lastPathComponent, "size": size as Any])
    case .saveAs(let temp):
      try? FileManager.default.removeItem(at: temp.deletingLastPathComponent())
      result(true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let taken = takePending() else { return }
    let (request, result) = taken
    if case .saveAs(let temp) = request {
      try? FileManager.default.removeItem(at: temp.deletingLastPathComponent())
      result(false)
    } else {
      result(nil)
    }
  }

  private func takePending() -> (Request, FlutterResult)? {
    guard let current = pending else { return nil }
    pending = nil
    return (current.request, current.result)
  }

  // MARK: Files

  private static func folderURL(_ uri: String) -> URL? {
    guard uri.hasPrefix(bookmarkScheme),
      let data = Data(base64Encoded: String(uri.dropFirst(bookmarkScheme.count)))
    else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
      return nil
    }
    return url
  }

  private static func requireFolder(_ uri: String?) throws -> URL {
    guard let uri, let url = folderURL(uri) else {
      throw CocoaError(.fileReadNoPermission)
    }
    return url
  }

  private static func copy(_ uri: String, to destination: URL) throws {
    let target = { (source: URL) in
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: source, to: destination)
    }
    // Base64 has no "#", so the first one ends the folder part.
    if let hash = uri.firstIndex(of: "#"), uri.hasPrefix(bookmarkScheme) {
      let folder = try requireFolder(String(uri[..<hash]))
      let name = String(uri[uri.index(after: hash)...])
      try accessing(folder) { try target(folder.appendingPathComponent(name)) }
    } else if let url = URL(string: uri) {
      try accessing(url) { try target(url) }
    } else {
      throw NSError(
        domain: "DocumentsChannel", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unknown document"])
    }
  }

  private static func accessing<T>(_ url: URL, _ body: () throws -> T) throws -> T {
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }
    return try body()
  }

  private func background(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let value = try work()
        DispatchQueue.main.async { result(value) }
      } catch let error as CocoaError where error.code == .fileReadNoPermission || error.code == .fileWriteNoPermission {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_access", message: error.localizedDescription, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "io_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
