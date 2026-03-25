import Foundation

enum SessionTransition: Equatable, Sendable {
  case needsAttention(scopedID: String, status: SessionDisplayStatus, title: String, detail: String?)
  case workComplete(scopedID: String, title: String, provider: Provider)
  case attentionCleared(scopedID: String)
}

enum SessionTransitionDiff {
  static func transitions(
    previous: [String: RootSessionNode],
    current: [String: RootSessionNode]
  ) -> [SessionTransition] {
    var result: [SessionTransition] = []
    var handledIDs: Set<String> = []

    // Check sessions present in current
    for (scopedID, node) in current {
      guard node.allowsUserNotifications else { continue }

      let prev = previous[scopedID]
      let prevStatus = prev?.displayStatus
      let curStatus = node.displayStatus

      // Skip sessions not relevant to notifications
      guard node.showsInMissionControl || (prev?.showsInMissionControl == true) else { continue }
      guard prevStatus != curStatus else { continue }

      handledIDs.insert(scopedID)

      let needsAttentionNow = curStatus == .permission || curStatus == .question
      let neededAttentionBefore = prevStatus == .permission || prevStatus == .question

      if needsAttentionNow, !neededAttentionBefore {
        result.append(.needsAttention(
          scopedID: scopedID,
          status: curStatus,
          title: node.title,
          detail: node.pendingToolName
        ))
      } else if neededAttentionBefore, !needsAttentionNow {
        result.append(.attentionCleared(scopedID: scopedID))
      }

      if prevStatus == .working, curStatus == .reply || curStatus == .ended {
        result.append(.workComplete(
          scopedID: scopedID,
          title: node.title,
          provider: node.provider
        ))
      }
    }

    // Sessions removed from current that were previously tracked
    for (scopedID, prev) in previous where !handledIDs.contains(scopedID) && current[scopedID] == nil {
      guard prev.allowsUserNotifications else { continue }

      let wasAttention = prev.displayStatus == .permission || prev.displayStatus == .question
      if wasAttention {
        result.append(.attentionCleared(scopedID: scopedID))
      }

      if prev.displayStatus == .working, prev.showsInMissionControl {
        result.append(.workComplete(
          scopedID: scopedID,
          title: prev.title,
          provider: prev.provider
        ))
      }
    }

    return result
  }
}
