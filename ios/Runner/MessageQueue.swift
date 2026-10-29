import Foundation

/// Messages the Shortcuts automation hands over, kept in a protected file
/// until the app has read them.
///
/// The file is readable only after the first unlock, so messages that
/// arrive while the iPhone is locked can still be added.
final class MessageQueue {
  static let shared = MessageQueue()

  /// Posted on the main queue with the new message under "message".
  static let didAppend = Notification.Name("PesaClarityMessageQueued")

  /// Messages left unread this long are dropped.
  static let retention: TimeInterval = 35 * 24 * 60 * 60

  private static let lastArrivalKey = "lastShortcutMessageMillis"

  struct Message: Codable {
    let sender: String
    let body: String
    let receivedAtMillis: Int64

    var asMap: [String: Any] {
      ["sender": sender, "body": body, "receivedAtMillis": receivedAtMillis]
    }
  }

  private let lock = NSLock()

  private var fileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("shortcut_messages.json")
  }

  func append(sender: String, body: String, receivedAt: Date = Date()) throws {
    let message = Message(
      sender: sender.trimmingCharacters(in: .whitespacesAndNewlines),
      body: body,
      receivedAtMillis: Int64(receivedAt.timeIntervalSince1970 * 1000)
    )
    try locked {
      let oldest = Int64((receivedAt.timeIntervalSince1970 - Self.retention) * 1000)
      var all = load().filter { $0.receivedAtMillis >= oldest }
      all.append(message)
      try save(all)
    }
    UserDefaults.standard.set(message.receivedAtMillis, forKey: Self.lastArrivalKey)
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: Self.didAppend, object: nil, userInfo: ["message": message])
    }
  }

  /// Queued messages from [senders] received at or after [sinceMillis],
  /// oldest first. Senders match without regard to case or spaces.
  func messages(senders: [String], sinceMillis: Int64) -> [Message] {
    let watched = Set(senders.map(Self.normalise))
    return locked { load() }
      .filter { watched.contains(Self.normalise($0.sender)) && $0.receivedAtMillis >= sinceMillis }
      .sorted { $0.receivedAtMillis < $1.receivedAtMillis }
  }

  /// Drops messages received before [beforeMillis], once they are read.
  func release(beforeMillis: Int64) throws {
    try locked {
      let all = load()
      let kept = all.filter { $0.receivedAtMillis >= beforeMillis }
      if kept.count != all.count { try save(kept) }
    }
  }

  /// When the last message arrived, or nil before the first.
  var lastArrivalMillis: Int64? {
    let value = UserDefaults.standard.object(forKey: Self.lastArrivalKey) as? NSNumber
    return value?.int64Value
  }

  static func normalise(_ sender: String) -> String {
    sender.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func load() -> [Message] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
  }

  private func save(_ messages: [Message]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(messages)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
