import Foundation

struct MissionWorktreeItem: Codable, Identifiable, Equatable {
  let id: String
  let branch: String
  let worktreePath: String
  let diskPresent: Bool
  let orchestrationState: OrchestrationState
  let issueIdentifier: String
  let issueTitle: String

  enum CodingKeys: String, CodingKey {
    case id, branch
    case worktreePath = "worktree_path"
    case diskPresent = "disk_present"
    case orchestrationState = "orchestration_state"
    case issueIdentifier = "issue_identifier"
    case issueTitle = "issue_title"
  }

  /// Whether this worktree is safe to pre-select for cleanup.
  var isCleanable: Bool {
    orchestrationState == .completed || orchestrationState == .failed
  }

  /// Whether an agent is still actively using this worktree.
  var isActive: Bool {
    orchestrationState == .running || orchestrationState == .claimed
  }
}
