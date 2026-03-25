import Foundation

#if DEBUG
  enum ConversationFollowDebug {
    private static let isEnabled = ProcessInfo.processInfo.environment["ORBITDOCK_CONVERSATION_DEBUG"] == "1"

    static func log(
      _ message: @autoclosure () -> String,
      file: StaticString = #fileID,
      line: UInt = #line
    ) {
      guard isEnabled else { return }
      let timestamp = ISO8601DateFormatter().string(from: Date())
      print("[ConversationFollow][\(timestamp)][\(file):\(line)] \(message())")
    }
  }
#else
  enum ConversationFollowDebug {
    static func log(
      _ message: @autoclosure () -> String,
      file _: StaticString = #fileID,
      line _: UInt = #line
    ) {}
  }
#endif
