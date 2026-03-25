//
//  ConversationCollectionTypes.swift
//  OrbitDock
//
//  Shared conversation types used across the app.
//

import Foundation

nonisolated enum ConversationScrollCommand: Equatable, Sendable {
  case latest(nonce: Int)
  case message(id: String, nonce: Int)

  var nonce: Int {
    switch self {
      case let .latest(nonce), let .message(_, nonce):
        nonce
    }
  }

  var messageID: String? {
    switch self {
      case .latest:
        nil
      case let .message(id, _):
        id
    }
  }
}

nonisolated enum ApprovalCardMode: Hashable, Sendable {
  case permission
  case question
  case takeover
  case passiveBlocked
  case none
}
