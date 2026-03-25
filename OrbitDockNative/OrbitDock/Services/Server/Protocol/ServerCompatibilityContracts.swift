import Foundation

enum OrbitDockProtocol {
  static let major: UInt16 = 2
  static let minor: UInt16 = 0
  static let clientVersion = "OrbitDockNative"
}

enum ServerSessionSurface: String, Codable, Sendable {
  case detail
  case composer
  case conversation
}

struct ServerHelloMetadata: Codable, Sendable {
  let serverVersion: String
  let protocolMajor: UInt16
  let protocolMinor: UInt16
  let capabilities: [String]

  enum CodingKeys: String, CodingKey {
    case serverVersion = "server_version"
    case protocolMajor = "protocol_major"
    case protocolMinor = "protocol_minor"
    case capabilities
  }
}

struct ServerMetaResponse: Codable, Sendable {
  let serverVersion: String
  let protocolMajor: UInt16
  let protocolMinor: UInt16
  let capabilities: [String]
  let isPrimary: Bool
  let clientPrimaryClaims: [ServerClientPrimaryClaim]

  enum CodingKeys: String, CodingKey {
    case serverVersion = "server_version"
    case protocolMajor = "protocol_major"
    case protocolMinor = "protocol_minor"
    case capabilities
    case isPrimary = "is_primary"
    case clientPrimaryClaims = "client_primary_claims"
  }
}

struct ServerDashboardCounts: Codable, Sendable {
  let attention: UInt32
  let running: UInt32
  let ready: UInt32
  let direct: UInt32
}

struct ServerDashboardSnapshotPayload: Codable, Sendable {
  let revision: UInt64
  let sessions: [ServerSessionListItem]
  let conversations: [ServerDashboardConversationItem]
  let counts: ServerDashboardCounts
}

struct ServerMissionSnapshotPayload: Codable, Sendable {
  let revision: UInt64
  let missions: [MissionSummary]
}

struct ServerSessionDetailSnapshotPayload: Codable, Sendable {
  let revision: UInt64
  let session: ServerSessionState
}

struct ServerSessionComposerSnapshotPayload: Codable, Sendable {
  let revision: UInt64
  let session: ServerSessionState
}

struct ServerConversationSnapshotPayload: Codable, Sendable {
  let revision: UInt64
  let sessionId: String
  let session: ServerSessionState
  let rows: [ServerConversationRowEntry]
  let totalRowCount: UInt64
  let hasMoreBefore: Bool
  let oldestSequence: UInt64?
  let newestSequence: UInt64?

  enum CodingKeys: String, CodingKey {
    case revision
    case sessionId = "session_id"
    case session
    case rows
    case totalRowCount = "total_row_count"
    case hasMoreBefore = "has_more_before"
    case oldestSequence = "oldest_sequence"
    case newestSequence = "newest_sequence"
  }
}
