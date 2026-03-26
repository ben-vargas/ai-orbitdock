import Foundation

#if DEBUG
  enum ConversationFollowDebug {
    static func log(
      _ message: @autoclosure () -> String,
      file: StaticString = #fileID,
      line: UInt = #line
    ) {
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
