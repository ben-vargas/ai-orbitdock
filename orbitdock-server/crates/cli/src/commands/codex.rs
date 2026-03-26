use orbitdock_protocol::CodexAccountStatus;
use serde::{Deserialize, Serialize};

use crate::cli::CodexAction;
use crate::client::rest::RestClient;
use crate::error::EXIT_SUCCESS;
use crate::output::Output;

#[derive(Debug, Deserialize, Serialize)]
struct CodexAccountResponse {
    status: CodexAccountStatus,
}

#[derive(Debug, Deserialize, Serialize)]
struct CodexLoginStartedResponse {
    login_id: String,
    auth_url: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct CodexLogoutResponse {
    status: CodexAccountStatus,
}

#[derive(Debug, Serialize)]
struct CodexAccountJsonResponse {
    kind: &'static str,
    logged_in: bool,
    login_in_progress: bool,
    status: CodexAccountStatus,
}

#[derive(Debug, Serialize)]
struct CodexLoginJsonResponse {
    ok: bool,
    action: &'static str,
    login_id: String,
    auth_url: String,
}

#[derive(Debug, Serialize)]
struct CodexLogoutJsonResponse {
    ok: bool,
    action: &'static str,
    logged_in: bool,
    login_in_progress: bool,
    status: CodexAccountStatus,
}

pub async fn run(action: &CodexAction, rest: &RestClient, output: &Output) -> i32 {
    match action {
        CodexAction::Account => account(rest, output).await,
        CodexAction::Login => login(rest, output).await,
        CodexAction::Logout => logout(rest, output).await,
    }
}

async fn account(rest: &RestClient, output: &Output) -> i32 {
    match rest
        .get::<CodexAccountResponse>("/api/codex/account")
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&CodexAccountJsonResponse {
                    kind: "codex_account",
                    logged_in: resp.status.account.is_some(),
                    login_in_progress: resp.status.login_in_progress,
                    status: resp.status,
                });
            } else {
                let bold = console::Style::new().bold();
                let logged_in = resp.status.account.is_some();
                let status_str = if logged_in {
                    "logged in"
                } else {
                    "not logged in"
                };
                println!("{} {}", bold.apply_to("Codex:"), status_str);
                if let Some(ref acct) = resp.status.account {
                    match acct {
                        orbitdock_protocol::CodexAccount::ApiKey => {
                            println!("{} API key", bold.apply_to("Auth:"));
                        }
                        orbitdock_protocol::CodexAccount::Chatgpt { email, plan_type } => {
                            if let Some(email) = email {
                                println!("{} {}", bold.apply_to("Email:"), email);
                            }
                            if let Some(plan) = plan_type {
                                println!("{} {}", bold.apply_to("Plan:"), plan);
                            }
                        }
                    }
                }
                if resp.status.login_in_progress {
                    println!("Login in progress...");
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

async fn login(rest: &RestClient, output: &Output) -> i32 {
    // Empty body for POST
    let body = serde_json::json!({});
    match rest
        .post_json::<_, CodexLoginStartedResponse>("/api/codex/login/start", &body)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&CodexLoginJsonResponse {
                    ok: true,
                    action: "codex_login_start",
                    login_id: resp.login_id,
                    auth_url: resp.auth_url,
                });
            } else {
                println!("Login started. Open this URL to authenticate:");
                println!("  {}", resp.auth_url);
                println!("\nLogin ID: {}", resp.login_id);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn logout(rest: &RestClient, output: &Output) -> i32 {
    let body = serde_json::json!({});
    match rest
        .post_json::<_, CodexLogoutResponse>("/api/codex/logout", &body)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&CodexLogoutJsonResponse {
                    ok: true,
                    action: "codex_logout",
                    logged_in: resp.status.account.is_some(),
                    login_in_progress: resp.status.login_in_progress,
                    status: resp.status,
                });
            } else {
                println!("Logged out.");
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}
