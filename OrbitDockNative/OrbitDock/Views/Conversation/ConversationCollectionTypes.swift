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
  case jumpToLatest(nonce: Int)
  case revealMessage(id: String, nonce: Int)
  case toggleFollow(nonce: Int)
  case openPendingApproval(nonce: Int)

  var nonce: Int {
    switch self {
      case let .latest(nonce),
           let .message(_, nonce),
           let .jumpToLatest(nonce),
           let .revealMessage(_, nonce),
           let .toggleFollow(nonce),
           let .openPendingApproval(nonce):
        nonce
    }
  }

  var messageID: String? {
    switch self {
      case .latest, .jumpToLatest, .toggleFollow, .openPendingApproval:
        nil
      case let .message(id, _), let .revealMessage(id, _):
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
