import AppIntents

/// The Shortcuts action "Add transaction from message". A personal
/// automation runs it for each message from M-Pesa or a bank, passing the
/// message and its sender. It only queues the message; the app reads it the
/// next time it opens, or at once if it is open.
struct AddTransactionFromMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "Add transaction from message"
  static var description = IntentDescription(
    "Sends an M-Pesa or bank message to Pesa Clarity. It stays on this iPhone.")
  static var openAppWhenRun = false

  @Parameter(title: "Message")
  var message: String

  @Parameter(title: "Sender")
  var sender: String

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$message) from \(\.$sender)")
  }

  func perform() async throws -> some IntentResult {
    try MessageQueue.shared.append(sender: sender, body: message)
    return .result()
  }
}
