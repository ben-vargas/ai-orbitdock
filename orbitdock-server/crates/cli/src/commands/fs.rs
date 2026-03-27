use orbitdock_protocol::{DirectoryEntry, RecentProject};
use serde::{Deserialize, Serialize};

use crate::cli::FsAction;
use crate::client::rest::RestClient;
use crate::error::EXIT_SUCCESS;
use crate::output::Output;

#[derive(Debug, Deserialize, Serialize)]
struct DirectoryListingResponse {
  path: String,
  entries: Vec<DirectoryEntry>,
}

#[derive(Debug, Deserialize, Serialize)]
struct RecentProjectsResponse {
  projects: Vec<RecentProject>,
}

#[derive(Debug, Serialize)]
struct BrowseSummary {
  path: String,
  entry_count: usize,
  directory_count: usize,
  file_count: usize,
  git_repo_count: usize,
}

#[derive(Debug, Serialize)]
struct BrowseJsonResponse {
  kind: &'static str,
  summary: BrowseSummary,
  listing: DirectoryListingResponse,
}

#[derive(Debug, Serialize)]
struct RecentProjectsJsonResponse {
  kind: &'static str,
  count: usize,
  projects: Vec<RecentProject>,
}

fn build_browse_json_response(resp: DirectoryListingResponse) -> BrowseJsonResponse {
  let directory_count = resp.entries.iter().filter(|entry| entry.is_dir).count();
  let git_repo_count = resp.entries.iter().filter(|entry| entry.is_git).count();
  let entry_count = resp.entries.len();
  BrowseJsonResponse {
    kind: "fs_browse",
    summary: BrowseSummary {
      path: resp.path.clone(),
      entry_count,
      directory_count,
      file_count: entry_count.saturating_sub(directory_count),
      git_repo_count,
    },
    listing: resp,
  }
}

pub async fn run(action: &FsAction, rest: &RestClient, output: &Output) -> i32 {
  match action {
    FsAction::Browse { path } => browse(rest, output, path.as_deref()).await,
    FsAction::Recent => recent(rest, output).await,
  }
}

async fn browse(rest: &RestClient, output: &Output, path: Option<&str>) -> i32 {
  let api_path = match path {
    Some(p) => format!("/api/fs/browse?path={}", urlencoding::encode(p)),
    None => "/api/fs/browse".to_string(),
  };

  match rest
    .get::<DirectoryListingResponse>(&api_path)
    .await
    .into_result()
  {
    Ok(resp) => {
      if output.json {
        output.print_json_pretty(&build_browse_json_response(resp));
      } else {
        let directory_count = resp.entries.iter().filter(|entry| entry.is_dir).count();
        let git_repo_count = resp.entries.iter().filter(|entry| entry.is_git).count();
        println!(
          "{}: {} item(s), {} director(y/ies), {} git repo(s)",
          resp.path,
          resp.entries.len(),
          directory_count,
          git_repo_count
        );
        for entry in &resp.entries {
          let icon = if entry.is_git {
            " [git]"
          } else if entry.is_dir {
            "/"
          } else {
            ""
          };
          println!("  {}{}", entry.name, icon);
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

async fn recent(rest: &RestClient, output: &Output) -> i32 {
  match rest
    .get::<RecentProjectsResponse>("/api/fs/recent-projects")
    .await
    .into_result()
  {
    Ok(resp) => {
      if output.json {
        output.print_json_pretty(&RecentProjectsJsonResponse {
          kind: "recent_projects",
          count: resp.projects.len(),
          projects: resp.projects,
        });
      } else if resp.projects.is_empty() {
        println!("No recent projects.");
      } else {
        println!("Recent projects ({}):", resp.projects.len());
        for p in &resp.projects {
          let last_active = p.last_active.as_deref().unwrap_or("unknown");
          println!(
            "  {} — {} session(s), last active {}",
            p.path, p.session_count, last_active
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
