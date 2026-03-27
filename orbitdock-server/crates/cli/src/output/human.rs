use comfy_table::{
  modifiers::UTF8_ROUND_CORNERS, presets::UTF8_FULL, Attribute, Cell, Color, Table,
};
use orbitdock_protocol::{
  ApprovalHistoryItem, Provider, SessionListItem, SessionStatus, WorkStatus,
};

use super::{relative_time_label, truncate};

/// Format sessions as a human-readable table.
pub fn sessions_table(sessions: &[SessionListItem]) {
  println!("{}", render_sessions_table(sessions));
}

fn render_sessions_table(sessions: &[SessionListItem]) -> String {
  if sessions.is_empty() {
    return "No sessions found.".to_string();
  }

  let mut table = Table::new();
  table
    .load_preset(UTF8_FULL)
    .apply_modifier(UTF8_ROUND_CORNERS)
    .set_header(vec![
      Cell::new("ID").add_attribute(Attribute::Bold),
      Cell::new("Provider").add_attribute(Attribute::Bold),
      Cell::new("Project").add_attribute(Attribute::Bold),
      Cell::new("Status").add_attribute(Attribute::Bold),
      Cell::new("Updated").add_attribute(Attribute::Bold),
      Cell::new("Unread").add_attribute(Attribute::Bold),
      Cell::new("Model").add_attribute(Attribute::Bold),
      Cell::new("Name").add_attribute(Attribute::Bold),
    ]);

  for s in sessions {
    let project = s
      .project_name
      .as_deref()
      .or(s.project_path.split('/').next_back())
      .unwrap_or("-");
    let provider = match s.provider {
      Provider::Claude => "claude",
      Provider::Codex => "codex",
    };
    let model = s.model.as_deref().unwrap_or("-");
    let updated = relative_time_label(s.last_activity_at.as_deref().or(s.started_at.as_deref()))
      .unwrap_or_else(|| "-".to_string());
    let name = s.display_title.as_str();
    let name_truncated = truncate(name, 32);

    table.add_row(vec![
      Cell::new(&s.id),
      Cell::new(provider),
      Cell::new(project),
      status_cell(s.status, s.work_status),
      Cell::new(updated),
      Cell::new(s.unread_count),
      Cell::new(model),
      Cell::new(name_truncated),
    ]);
  }

  table.to_string()
}

/// Format approval history as a human-readable table.
pub fn approvals_table(approvals: &[ApprovalHistoryItem]) {
  println!("{}", render_approvals_table(approvals));
}

fn render_approvals_table(approvals: &[ApprovalHistoryItem]) -> String {
  if approvals.is_empty() {
    return "No approvals found.".to_string();
  }

  let mut table = Table::new();
  table
    .load_preset(UTF8_FULL)
    .apply_modifier(UTF8_ROUND_CORNERS)
    .set_header(vec![
      Cell::new("ID").add_attribute(Attribute::Bold),
      Cell::new("Session").add_attribute(Attribute::Bold),
      Cell::new("Type").add_attribute(Attribute::Bold),
      Cell::new("Tool").add_attribute(Attribute::Bold),
      Cell::new("Decision").add_attribute(Attribute::Bold),
      Cell::new("Created").add_attribute(Attribute::Bold),
    ]);

  for a in approvals {
    let approval_type = format!("{:?}", a.approval_type).to_lowercase();
    let tool = a.tool_name.as_deref().unwrap_or("-");
    let decision = a.decision.as_deref().unwrap_or("pending");

    table.add_row(vec![
      Cell::new(a.id),
      Cell::new(&a.session_id),
      Cell::new(approval_type),
      Cell::new(tool),
      Cell::new(decision),
      Cell::new(&a.created_at),
    ]);
  }

  table.to_string()
}

fn status_cell(status: SessionStatus, work_status: WorkStatus) -> Cell {
  let (label, color) = match (status, work_status) {
    (SessionStatus::Ended, _) | (_, WorkStatus::Ended) => ("ended", Color::DarkGrey),
    (_, WorkStatus::Working) => ("working", Color::Cyan),
    (_, WorkStatus::Permission) => ("permission", Color::Red),
    (_, WorkStatus::Question) => ("question", Color::Magenta),
    (_, WorkStatus::Reply) => ("reply", Color::Blue),
    (_, WorkStatus::Waiting) => ("waiting", Color::Yellow),
  };
  Cell::new(label).fg(color)
}

#[cfg(test)]
mod tests {
  use orbitdock_protocol::{
    SessionControlMode, SessionLifecycleState, SessionListItem, SessionListStatus, SessionStatus,
    WorkStatus,
  };

  use super::render_sessions_table;

  #[test]
  fn session_table_preserves_full_session_ids() {
    let session_id = "od-f90e8471-777c-4db5-9de5-9dd90ca0c55c";
    let table = render_sessions_table(&[SessionListItem {
      id: session_id.to_string(),
      provider: orbitdock_protocol::Provider::Claude,
      project_path: "/tmp/orbitdock".to_string(),
      project_name: Some("OrbitDock".to_string()),
      git_branch: Some("main".to_string()),
      model: Some("claude-opus-4-6".to_string()),
      status: SessionStatus::Active,
      work_status: WorkStatus::Waiting,
      control_mode: SessionControlMode::Direct,
      lifecycle_state: SessionLifecycleState::Open,
      steerable: true,
      codex_integration_mode: None,
      claude_integration_mode: None,
      started_at: None,
      last_activity_at: None,
      last_progress_at: None,
      unread_count: 0,
      has_turn_diff: false,
      pending_tool_name: None,
      repository_root: None,
      is_worktree: false,
      worktree_id: None,
      total_tokens: 0,
      total_cost_usd: 0.0,
      input_tokens: 0,
      output_tokens: 0,
      cached_tokens: 0,
      display_title: "CLI Session Output Formatter".to_string(),
      context_line: None,
      list_status: SessionListStatus::Working,
      effort: None,
      summary_revision: 0,
      active_worker_count: 0,
      pending_tool_family: None,
      forked_from_session_id: None,
      mission_id: None,
      issue_identifier: None,
    }]);

    assert!(table.contains(session_id));
    assert!(!table.contains("od-f90e8471-777..."));
    assert!(table.contains("Updated"));
    assert!(table.contains("Unread"));
  }
}
