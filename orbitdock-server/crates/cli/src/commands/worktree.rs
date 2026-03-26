use orbitdock_protocol::WorktreeSummary;
use serde::{Deserialize, Serialize};

use crate::cli::WorktreeAction;
use crate::client::rest::RestClient;
use crate::error::EXIT_SUCCESS;
use crate::output::Output;

#[derive(Debug, Deserialize, Serialize)]
struct WorktreesListResponse {
    repo_root: Option<String>,
    worktrees: Vec<WorktreeSummary>,
}

#[derive(Debug, Deserialize, Serialize)]
struct WorktreeCreatedResponse {
    worktree: WorktreeSummary,
}

#[derive(Debug, Deserialize, Serialize)]
struct WorktreeRemovedResponse {
    worktree_id: String,
    ok: bool,
}

#[derive(Debug, Serialize)]
struct CreateWorktreeRequest {
    repo_path: String,
    branch_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    base_branch: Option<String>,
}

#[derive(Debug, Serialize)]
struct DiscoverWorktreesRequest {
    repo_path: String,
}

#[derive(Debug, Serialize)]
struct WorktreeListSummary {
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_root: Option<String>,
    count: usize,
    active_count: usize,
}

#[derive(Debug, Serialize)]
struct WorktreeListJsonResponse {
    kind: &'static str,
    summary: WorktreeListSummary,
    worktrees: Vec<WorktreeSummary>,
}

#[derive(Debug, Serialize)]
struct WorktreeActionJsonResponse {
    ok: bool,
    action: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    worktree_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    worktree: Option<WorktreeSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    worktrees: Option<Vec<WorktreeSummary>>,
}

fn build_worktree_list_json_response(resp: WorktreesListResponse) -> WorktreeListJsonResponse {
    let active_count = resp
        .worktrees
        .iter()
        .filter(|worktree| worktree.status.as_str() == "active")
        .count();
    WorktreeListJsonResponse {
        kind: "worktree_list",
        summary: WorktreeListSummary {
            repo_root: resp.repo_root,
            count: resp.worktrees.len(),
            active_count,
        },
        worktrees: resp.worktrees,
    }
}

pub async fn run(action: &WorktreeAction, rest: &RestClient, output: &Output) -> i32 {
    match action {
        WorktreeAction::List { repo } => list(rest, output, repo.as_deref()).await,
        WorktreeAction::Create { repo, branch, base } => {
            create(rest, output, repo, branch, base.as_deref()).await
        }
        WorktreeAction::Discover { repo } => discover(rest, output, repo).await,
        WorktreeAction::Remove {
            worktree_id,
            force,
            delete_branch,
            delete_remote_branch,
        } => {
            remove(
                rest,
                output,
                worktree_id,
                *force,
                *delete_branch,
                *delete_remote_branch,
            )
            .await
        }
    }
}

async fn list(rest: &RestClient, output: &Output, repo: Option<&str>) -> i32 {
    let path = match repo {
        Some(r) => format!("/api/worktrees?repo_root={}", urlencoding::encode(r)),
        None => "/api/worktrees".to_string(),
    };

    match rest.get::<WorktreesListResponse>(&path).await.into_result() {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&build_worktree_list_json_response(resp));
            } else if resp.worktrees.is_empty() {
                println!("No worktrees found.");
            } else {
                println!("Worktrees ({}):", resp.worktrees.len());
                for w in &resp.worktrees {
                    let status = w.status.as_str();
                    println!(
                        "  {} ({}) - {} [{}]",
                        w.branch, status, w.worktree_path, w.id
                    );
                }
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn create(
    rest: &RestClient,
    output: &Output,
    repo: &str,
    branch: &str,
    base: Option<&str>,
) -> i32 {
    let body = CreateWorktreeRequest {
        repo_path: repo.to_string(),
        branch_name: branch.to_string(),
        base_branch: base.map(|s| s.to_string()),
    };
    match rest
        .post_json::<_, WorktreeCreatedResponse>("/api/worktrees", &body)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&WorktreeActionJsonResponse {
                    ok: true,
                    action: "created",
                    worktree_id: Some(resp.worktree.id.clone()),
                    worktree: Some(resp.worktree),
                    worktrees: None,
                });
            } else {
                println!(
                    "Created worktree {} at {} [{}]",
                    resp.worktree.branch, resp.worktree.worktree_path, resp.worktree.id
                );
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn discover(rest: &RestClient, output: &Output, repo: &str) -> i32 {
    let body = DiscoverWorktreesRequest {
        repo_path: repo.to_string(),
    };
    match rest
        .post_json::<_, WorktreesListResponse>("/api/worktrees/discover", &body)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&WorktreeActionJsonResponse {
                    ok: true,
                    action: "discovered",
                    worktree_id: None,
                    worktree: None,
                    worktrees: Some(resp.worktrees),
                });
            } else {
                println!("Discovered {} worktree(s):", resp.worktrees.len());
                for w in &resp.worktrees {
                    println!(
                        "  {} - {} [{}]",
                        w.branch,
                        w.worktree_path,
                        w.status.as_str()
                    );
                }
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn remove(
    rest: &RestClient,
    output: &Output,
    worktree_id: &str,
    force: bool,
    delete_branch: bool,
    delete_remote_branch: bool,
) -> i32 {
    let mut query_parts = Vec::new();
    if force {
        query_parts.push("force=true".to_string());
    }
    if delete_branch {
        query_parts.push("delete_branch=true".to_string());
    }
    if delete_remote_branch {
        query_parts.push("delete_remote_branch=true".to_string());
    }

    let path = if query_parts.is_empty() {
        format!("/api/worktrees/{worktree_id}")
    } else {
        format!("/api/worktrees/{worktree_id}?{}", query_parts.join("&"))
    };

    match rest
        .delete::<WorktreeRemovedResponse>(&path)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&WorktreeActionJsonResponse {
                    ok: resp.ok,
                    action: "removed",
                    worktree_id: Some(resp.worktree_id),
                    worktree: None,
                    worktrees: None,
                });
            } else if resp.ok {
                println!("Worktree {} removed.", worktree_id);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}
