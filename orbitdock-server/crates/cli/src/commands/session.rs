use std::collections::HashSet;
use std::time::Duration;

use orbitdock_protocol::{
    conversation_contracts::extract_row_content_str_summary, ClientMessage,
    ConversationSnapshotPage, DashboardSnapshot, Provider, ServerMessage, SessionDetailSnapshot,
    SessionState, SessionStatus, SessionSummary, SessionSurface, ToolApprovalDecision, WorkStatus,
};
use serde::{Deserialize, Serialize};

use crate::cli::{
    resolve_stdin, ApprovalDecision, Effort, PermissionMode, ProviderFilter, SessionAction,
    StatusFilter,
};
use crate::client::config::ClientConfig;
use crate::client::rest::RestClient;
use crate::client::ws::WsClient;
use crate::error::{
    CliError, EXIT_CLIENT_ERROR, EXIT_CONNECTION_ERROR, EXIT_SERVER_ERROR, EXIT_SUCCESS,
};
use crate::output::{human, truncate, Output};

#[derive(Debug, Deserialize, Serialize)]
struct SessionsResponse {
    sessions: Vec<orbitdock_protocol::SessionListItem>,
}

#[derive(Debug, Deserialize, Serialize)]
struct CreateSessionRequest {
    provider: Provider,
    cwd: String,
    model: Option<String>,
    approval_policy: Option<String>,
    approval_policy_details: Option<orbitdock_protocol::CodexApprovalPolicy>,
    sandbox_mode: Option<String>,
    permission_mode: Option<String>,
    allowed_tools: Vec<String>,
    disallowed_tools: Vec<String>,
    effort: Option<String>,
    collaboration_mode: Option<String>,
    multi_agent: Option<bool>,
    personality: Option<String>,
    service_tier: Option<String>,
    developer_instructions: Option<String>,
    system_prompt: Option<String>,
    append_system_prompt: Option<String>,
    allow_bypass_permissions: bool,
    codex_config_mode: Option<orbitdock_protocol::CodexConfigMode>,
    codex_config_profile: Option<String>,
    codex_model_provider: Option<String>,
    codex_config_source: Option<orbitdock_protocol::CodexConfigSource>,
}

#[derive(Debug, Deserialize, Serialize)]
struct CreateSessionResponse {
    session_id: String,
    session: SessionSummary,
}

#[derive(Debug, Deserialize, Serialize)]
struct ResumeSessionResponse {
    session_id: String,
    session: SessionSummary,
}

#[derive(Debug, Deserialize, Serialize)]
struct ForkSessionRequest {
    nth_user_message: Option<u32>,
    model: Option<String>,
    approval_policy: Option<String>,
    sandbox_mode: Option<String>,
    cwd: Option<String>,
    permission_mode: Option<String>,
    allowed_tools: Vec<String>,
    disallowed_tools: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct ForkSessionResponse {
    source_session_id: String,
    new_session_id: String,
    session: SessionSummary,
}

pub async fn run(
    action: &SessionAction,
    rest: &RestClient,
    output: &Output,
    config: &ClientConfig,
) -> i32 {
    match action {
        // REST commands
        SessionAction::List {
            provider,
            status,
            project,
        } => {
            list(
                rest,
                output,
                provider.as_ref(),
                status.as_ref(),
                project.as_deref(),
            )
            .await
        }
        SessionAction::Get {
            session_id,
            messages,
        } => get(rest, output, session_id, *messages).await,

        // WS commands
        SessionAction::Create {
            provider,
            cwd,
            model,
            permission_mode,
            effort,
            system_prompt,
        } => {
            let resolved_cwd = match cwd {
                Some(c) => c.clone(),
                None => std::env::current_dir()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_else(|_| ".".to_string()),
            };
            create(CreateSessionArgs {
                rest,
                output,
                provider_filter: provider,
                cwd: &resolved_cwd,
                model: model.as_deref(),
                permission_mode: permission_mode.as_ref(),
                effort: effort.as_ref(),
                system_prompt: system_prompt.as_deref(),
            })
            .await
        }
        SessionAction::Send {
            session_id,
            content,
            model,
            effort,
            no_wait,
        } => {
            let resolved = match resolve_stdin(content) {
                Ok(c) => c,
                Err(e) => {
                    output.print_error(&CliError::new("stdin_error", e.to_string()));
                    return EXIT_CLIENT_ERROR;
                }
            };
            send_message(
                config,
                output,
                session_id,
                &resolved,
                model.as_deref(),
                effort.as_ref(),
                *no_wait,
            )
            .await
        }
        SessionAction::Approve {
            session_id,
            decision,
            message,
            request_id,
        } => {
            approve_tool(
                config,
                output,
                session_id,
                decision,
                message.as_deref(),
                request_id.as_deref(),
            )
            .await
        }
        SessionAction::Answer {
            session_id,
            answer,
            request_id,
        } => {
            let resolved = match resolve_stdin(answer) {
                Ok(a) => a,
                Err(e) => {
                    output.print_error(&CliError::new("stdin_error", e.to_string()));
                    return EXIT_CLIENT_ERROR;
                }
            };
            answer_question(config, output, session_id, &resolved, request_id.as_deref()).await
        }
        SessionAction::Interrupt { session_id } => interrupt(config, output, session_id).await,
        SessionAction::End { session_id } => end_session(config, output, session_id).await,
        SessionAction::Fork {
            session_id,
            nth_user_message,
            model,
        } => {
            fork(
                rest,
                output,
                session_id,
                *nth_user_message,
                model.as_deref(),
            )
            .await
        }
        SessionAction::Steer {
            session_id,
            content,
        } => {
            let resolved = match resolve_stdin(content) {
                Ok(c) => c,
                Err(e) => {
                    output.print_error(&CliError::new("stdin_error", e.to_string()));
                    return EXIT_CLIENT_ERROR;
                }
            };
            steer(config, output, session_id, &resolved).await
        }
        SessionAction::Compact { session_id } => compact(config, output, session_id).await,
        SessionAction::Undo { session_id } => undo(config, output, session_id).await,
        SessionAction::Rollback { session_id, turns } => {
            rollback(config, output, session_id, *turns).await
        }
        SessionAction::Watch {
            session_id,
            filter,
            timeout,
        } => watch(rest, config, output, session_id, filter, *timeout).await,
        SessionAction::Rename { session_id, name } => {
            rename(config, output, session_id, name).await
        }
        SessionAction::Resume { session_id } => resume(rest, output, session_id).await,
    }
}

// ── Helpers ──────────────────────────────────────────────────

async fn ws_connect(config: &ClientConfig, output: &Output) -> Option<WsClient> {
    match WsClient::connect(config).await {
        Ok(ws) => Some(ws),
        Err(e) => {
            output.print_error(&CliError::connection(e.to_string()));
            None
        }
    }
}

async fn fetch_session_detail_snapshot(
    config: &ClientConfig,
    session_id: &str,
) -> Result<SessionDetailSnapshot, CliError> {
    let rest = RestClient::new(config);
    rest.get::<SessionDetailSnapshot>(&format!("/api/sessions/{session_id}/detail"))
        .await
        .into_result()
        .map_err(|(_, err)| err)
}

async fn fetch_conversation_snapshot(
    config: &ClientConfig,
    session_id: &str,
    limit: usize,
) -> Result<ConversationSnapshotPage, CliError> {
    let rest = RestClient::new(config);
    rest.get::<ConversationSnapshotPage>(&format!(
        "/api/sessions/{session_id}/conversation?limit={limit}"
    ))
    .await
    .into_result()
    .map_err(|(_, err)| err)
}

async fn subscribe_session_surface(
    ws: &mut WsClient,
    session_id: &str,
    surface: SessionSurface,
    since_revision: Option<u64>,
) -> Result<(), CliError> {
    ws.send(&ClientMessage::SubscribeSessionSurface {
        session_id: session_id.to_string(),
        surface,
        since_revision,
    })
    .await
    .map_err(|error| CliError::connection(error.to_string()))
}

async fn bootstrap_session_subscription(
    config: &ClientConfig,
    ws: &mut WsClient,
    session_id: &str,
) -> Result<SessionState, CliError> {
    let snapshot = fetch_session_detail_snapshot(config, session_id).await?;
    subscribe_session_surface(
        ws,
        session_id,
        SessionSurface::Detail,
        Some(snapshot.revision),
    )
    .await?;
    Ok(snapshot.session)
}

fn pending_request_id(session: &SessionState) -> Option<&str> {
    session.pending_approval.as_ref().map(|req| req.id.as_str())
}

fn provider_str(p: &Provider) -> &'static str {
    match p {
        Provider::Claude => "claude",
        Provider::Codex => "codex",
    }
}

fn session_status_str(s: &SessionStatus) -> &'static str {
    match s {
        SessionStatus::Active => "active",
        SessionStatus::Ended => "ended",
    }
}

fn work_status_str(s: &WorkStatus) -> &'static str {
    match s {
        WorkStatus::Working => "working",
        WorkStatus::Waiting => "waiting",
        WorkStatus::Permission => "permission",
        WorkStatus::Question => "question",
        WorkStatus::Reply => "reply",
        WorkStatus::Ended => "ended",
    }
}

fn stream_turn_should_exit(status: &WorkStatus, saw_turn_activity: bool) -> bool {
    match status {
        WorkStatus::Working => false,
        WorkStatus::Waiting => saw_turn_activity,
        _ => true,
    }
}

// ── REST Commands ────────────────────────────────────────────

async fn list(
    rest: &RestClient,
    output: &Output,
    provider: Option<&ProviderFilter>,
    status: Option<&StatusFilter>,
    project: Option<&str>,
) -> i32 {
    match rest
        .get::<DashboardSnapshot>("/api/dashboard")
        .await
        .into_result()
    {
        Ok(snapshot) => {
            let mut resp = SessionsResponse {
                sessions: snapshot.sessions,
            };
            if let Some(p) = provider {
                let target = match p {
                    ProviderFilter::Claude => Provider::Claude,
                    ProviderFilter::Codex => Provider::Codex,
                };
                resp.sessions.retain(|s| s.provider == target);
            }
            if let Some(s) = status {
                let target = match s {
                    StatusFilter::Active => orbitdock_protocol::SessionStatus::Active,
                    StatusFilter::Ended => orbitdock_protocol::SessionStatus::Ended,
                };
                resp.sessions.retain(|s| s.status == target);
            }
            if let Some(proj) = project {
                resp.sessions.retain(|s| s.project_path.contains(proj));
            }

            if output.json {
                output.print_json(&resp);
            } else {
                human::sessions_table(&resp.sessions);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn get(rest: &RestClient, output: &Output, session_id: &str, messages: bool) -> i32 {
    let path = if messages {
        format!("/api/sessions/{session_id}/detail?include_messages=true")
    } else {
        format!("/api/sessions/{session_id}/detail")
    };
    match rest.get::<SessionDetailSnapshot>(&path).await.into_result() {
        Ok(snapshot) => {
            if output.json {
                output.print_json(&snapshot);
            } else {
                print_session_detail(&snapshot.session, messages);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

// ── WS Commands ──────────────────────────────────────────────

struct CreateSessionArgs<'a> {
    rest: &'a RestClient,
    output: &'a Output,
    provider_filter: &'a ProviderFilter,
    cwd: &'a str,
    model: Option<&'a str>,
    permission_mode: Option<&'a PermissionMode>,
    effort: Option<&'a Effort>,
    system_prompt: Option<&'a str>,
}

async fn create(args: CreateSessionArgs<'_>) -> i32 {
    let CreateSessionArgs {
        rest,
        output,
        provider_filter,
        cwd,
        model,
        permission_mode,
        effort,
        system_prompt,
    } = args;

    let provider = match provider_filter {
        ProviderFilter::Claude => Provider::Claude,
        ProviderFilter::Codex => Provider::Codex,
    };

    let request = CreateSessionRequest {
        provider,
        cwd: cwd.to_string(),
        model: model.map(str::to_string),
        approval_policy: None,
        approval_policy_details: None,
        sandbox_mode: None,
        permission_mode: permission_mode.map(|m| m.as_str().to_string()),
        allowed_tools: vec![],
        disallowed_tools: vec![],
        effort: effort.map(|e| e.as_str().to_string()),
        collaboration_mode: None,
        multi_agent: None,
        personality: None,
        service_tier: None,
        developer_instructions: None,
        system_prompt: system_prompt.map(str::to_string),
        append_system_prompt: None,
        allow_bypass_permissions: false,
        codex_config_mode: None,
        codex_config_profile: None,
        codex_model_provider: None,
        codex_config_source: None,
    };

    match rest
        .post_json::<_, CreateSessionResponse>("/api/sessions", &request)
        .await
        .into_result()
    {
        Ok(resp) => {
            let session = resp.session;
            if output.json {
                output.print_json(&serde_json::json!({
                    "session_id": session.id,
                    "provider": provider_str(&session.provider),
                    "project_path": session.project_path,
                    "status": work_status_str(&session.work_status),
                }));
            } else {
                let bold = console::Style::new().bold();
                println!("{} {}", bold.apply_to("Created session:"), session.id);
                println!(
                    "{} {}",
                    bold.apply_to("Provider:"),
                    provider_str(&session.provider)
                );
                println!("{} {}", bold.apply_to("Project:"), session.project_path);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn send_message(
    config: &ClientConfig,
    output: &Output,
    session_id: &str,
    content: &str,
    model: Option<&str>,
    effort: Option<&Effort>,
    no_wait: bool,
) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    let conversation_revision = match fetch_conversation_snapshot(config, session_id, 50).await {
        Ok(snapshot) => snapshot.revision,
        Err(err) => {
            output.print_error(&err);
            return EXIT_SERVER_ERROR;
        }
    };

    if let Err(err) = subscribe_session_surface(
        &mut ws,
        session_id,
        SessionSurface::Conversation,
        Some(conversation_revision),
    )
    .await
    {
        output.print_error(&err);
        return EXIT_CONNECTION_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::SendMessage {
            session_id: session_id.to_string(),
            content: content.to_string(),
            model: model.map(str::to_string),
            effort: effort.map(|e| e.as_str().to_string()),
            skills: vec![],
            images: vec![],
            mentions: vec![],
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    if no_wait {
        if output.json {
            output.print_json(&serde_json::json!({"sent": true, "session_id": session_id}));
        } else {
            println!("Message sent.");
        }
        return EXIT_SUCCESS;
    }

    stream_turn_events(&mut ws, output).await
}

async fn approve_tool(
    config: &ClientConfig,
    output: &Output,
    session_id: &str,
    decision: &ApprovalDecision,
    message: Option<&str>,
    request_id: Option<&str>,
) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    let session = match bootstrap_session_subscription(config, &mut ws, session_id).await {
        Ok(session) => session,
        Err(err) => {
            output.print_error(&err);
            return EXIT_SERVER_ERROR;
        }
    };

    let resolved_id = match request_id {
        Some(id) => id.to_string(),
        None => match pending_request_id(&session) {
            Some(id) => id.to_string(),
            None => {
                output.print_error(&CliError::new(
                    "no_pending_approval",
                    "No pending approval. Use --request-id to specify one.",
                ));
                return EXIT_CLIENT_ERROR;
            }
        },
    };

    if let Err(e) = ws
        .send(&ClientMessage::ApproveTool {
            session_id: session_id.to_string(),
            request_id: resolved_id.clone(),
            decision: match decision {
                ApprovalDecision::Approved => ToolApprovalDecision::Approved,
                ApprovalDecision::ApprovedForSession => ToolApprovalDecision::ApprovedForSession,
                ApprovalDecision::ApprovedAlways => ToolApprovalDecision::ApprovedAlways,
                ApprovalDecision::Denied => ToolApprovalDecision::Denied,
                ApprovalDecision::Abort => ToolApprovalDecision::Abort,
            },
            message: message.map(str::to_string),
            interrupt: None,
            updated_input: None,
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(10)).await {
            Ok(Some(ServerMessage::ApprovalDecisionResult {
                ref request_id,
                ref outcome,
                ..
            })) if *request_id == resolved_id => {
                if output.json {
                    output.print_json(&serde_json::json!({
                        "request_id": request_id,
                        "outcome": outcome,
                    }));
                } else {
                    let bold = console::Style::new().bold();
                    println!(
                        "{} {} ({})",
                        bold.apply_to("Approval:"),
                        outcome,
                        request_id
                    );
                }
                return EXIT_SUCCESS;
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                output.print_error(&CliError::connection(
                    "Timed out waiting for approval result",
                ));
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn answer_question(
    config: &ClientConfig,
    output: &Output,
    session_id: &str,
    answer: &str,
    request_id: Option<&str>,
) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    let session = match bootstrap_session_subscription(config, &mut ws, session_id).await {
        Ok(session) => session,
        Err(err) => {
            output.print_error(&err);
            return EXIT_SERVER_ERROR;
        }
    };

    let resolved_id = match request_id {
        Some(id) => id.to_string(),
        None => match pending_request_id(&session) {
            Some(id) => id.to_string(),
            None => {
                output.print_error(&CliError::new(
                    "no_pending_question",
                    "No pending question. Use --request-id to specify one.",
                ));
                return EXIT_CLIENT_ERROR;
            }
        },
    };

    if let Err(e) = ws
        .send(&ClientMessage::AnswerQuestion {
            session_id: session_id.to_string(),
            request_id: resolved_id.clone(),
            answer: answer.to_string(),
            question_id: None,
            answers: None,
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(10)).await {
            Ok(Some(ServerMessage::ApprovalDecisionResult {
                ref request_id,
                ref outcome,
                ..
            })) if *request_id == resolved_id => {
                if output.json {
                    output.print_json(&serde_json::json!({
                        "request_id": request_id,
                        "outcome": outcome,
                    }));
                } else {
                    println!("Answer submitted ({outcome})");
                }
                return EXIT_SUCCESS;
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                output.print_error(&CliError::connection("Timed out"));
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn interrupt(config: &ClientConfig, output: &Output, session_id: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::InterruptSession {
            session_id: session_id.to_string(),
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(5)).await {
            Ok(Some(ServerMessage::SessionDelta { changes, .. })) => {
                if let Some(status) = changes.work_status.as_ref() {
                    if *status != WorkStatus::Working {
                        if output.json {
                            output.print_json(
                                &serde_json::json!({"interrupted": true, "work_status": work_status_str(status)}),
                            );
                        } else {
                            println!("Session interrupted. Status: {}", work_status_str(status));
                        }
                        return EXIT_SUCCESS;
                    }
                }
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                if output.json {
                    output.print_json(&serde_json::json!({"interrupted": true}));
                } else {
                    println!("Interrupt sent.");
                }
                return EXIT_SUCCESS;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn end_session(config: &ClientConfig, output: &Output, session_id: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::EndSession {
            session_id: session_id.to_string(),
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(10)).await {
            Ok(Some(ServerMessage::SessionEnded { reason, .. })) => {
                if output.json {
                    output.print_json(&serde_json::json!({"ended": true, "reason": reason}));
                } else {
                    println!("Session ended: {reason}");
                }
                return EXIT_SUCCESS;
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                if output.json {
                    output.print_json(&serde_json::json!({"ended": true}));
                } else {
                    println!("End request sent.");
                }
                return EXIT_SUCCESS;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn fork(
    rest: &RestClient,
    output: &Output,
    session_id: &str,
    nth_user_message: Option<u32>,
    model: Option<&str>,
) -> i32 {
    let request = ForkSessionRequest {
        nth_user_message,
        model: model.map(str::to_string),
        approval_policy: None,
        sandbox_mode: None,
        cwd: None,
        permission_mode: None,
        allowed_tools: vec![],
        disallowed_tools: vec![],
    };

    match rest
        .post_json::<_, ForkSessionResponse>(&format!("/api/sessions/{session_id}/fork"), &request)
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json(&serde_json::json!({
                    "forked": true,
                    "source_session_id": resp.source_session_id,
                    "new_session_id": resp.new_session_id,
                }));
            } else {
                let bold = console::Style::new().bold();
                println!(
                    "{} {} (from {})",
                    bold.apply_to("Forked:"),
                    resp.new_session_id,
                    resp.source_session_id
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

async fn steer(config: &ClientConfig, output: &Output, session_id: &str, content: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::SteerTurn {
            session_id: session_id.to_string(),
            content: content.to_string(),
            images: vec![],
            mentions: vec![],
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    if output.json {
        output.print_json(&serde_json::json!({"steered": true, "session_id": session_id}));
    } else {
        println!("Guidance injected.");
    }
    EXIT_SUCCESS
}

async fn compact(config: &ClientConfig, output: &Output, session_id: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::CompactContext {
            session_id: session_id.to_string(),
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(60)).await {
            Ok(Some(ServerMessage::ContextCompacted { .. })) => {
                if output.json {
                    output.print_json(&serde_json::json!({"compacted": true}));
                } else {
                    println!("Context compacted.");
                }
                return EXIT_SUCCESS;
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                output.print_error(&CliError::connection("Timed out waiting for compaction"));
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn undo(config: &ClientConfig, output: &Output, session_id: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::UndoLastTurn {
            session_id: session_id.to_string(),
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(30)).await {
            Ok(Some(ServerMessage::UndoCompleted {
                success, message, ..
            })) => {
                if output.json {
                    output.print_json(&serde_json::json!({"undone": success, "message": message}));
                } else if success {
                    println!(
                        "Undo complete.{}",
                        message.map(|m| format!(" {m}")).unwrap_or_default()
                    );
                } else {
                    eprintln!(
                        "Undo failed.{}",
                        message.map(|m| format!(" {m}")).unwrap_or_default()
                    );
                }
                return if success {
                    EXIT_SUCCESS
                } else {
                    EXIT_SERVER_ERROR
                };
            }
            Ok(Some(ServerMessage::UndoStarted { .. })) => continue,
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                output.print_error(&CliError::connection("Timed out waiting for undo"));
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn rollback(config: &ClientConfig, output: &Output, session_id: &str, turns: u32) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(err) = bootstrap_session_subscription(config, &mut ws, session_id).await {
        output.print_error(&err);
        return EXIT_SERVER_ERROR;
    }

    if let Err(e) = ws
        .send(&ClientMessage::RollbackTurns {
            session_id: session_id.to_string(),
            num_turns: turns,
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    loop {
        match ws.recv_timeout(Duration::from_secs(30)).await {
            Ok(Some(ServerMessage::ThreadRolledBack { num_turns, .. })) => {
                if output.json {
                    output.print_json(&serde_json::json!({"rolled_back": num_turns}));
                } else {
                    println!("Rolled back {num_turns} turn(s).");
                }
                return EXIT_SUCCESS;
            }
            Ok(Some(ServerMessage::Error { code, message, .. })) => {
                output.print_error(&CliError::new(code, message));
                return EXIT_SERVER_ERROR;
            }
            Ok(Some(_)) => continue,
            Ok(None) => {
                output.print_error(&CliError::connection("Timed out"));
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn watch(
    rest: &RestClient,
    config: &ClientConfig,
    output: &Output,
    session_id: &str,
    filter: &[String],
    timeout_secs: Option<u64>,
) -> i32 {
    let detail = match rest
        .get::<SessionDetailSnapshot>(&format!("/api/sessions/{session_id}/detail"))
        .await
        .into_result()
    {
        Ok(snapshot) => snapshot,
        Err((code, err)) => {
            output.print_error(&err);
            return code;
        }
    };
    let conversation = match rest
        .get::<ConversationSnapshotPage>(&format!(
            "/api/sessions/{session_id}/conversation?limit=200"
        ))
        .await
        .into_result()
    {
        Ok(snapshot) => snapshot,
        Err((code, err)) => {
            output.print_error(&err);
            return code;
        }
    };

    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(e) = ws
        .subscribe_session_surface(session_id, SessionSurface::Detail, Some(detail.revision))
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }
    if let Err(e) = ws
        .subscribe_session_surface(
            session_id,
            SessionSurface::Conversation,
            Some(conversation.revision),
        )
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    if output.json {
        output.print_json(&serde_json::json!({
            "type": "bootstrap_detail",
            "snapshot": detail,
        }));
        output.print_json(&serde_json::json!({
            "type": "bootstrap_conversation",
            "snapshot": conversation,
        }));
    } else {
        let bold = console::Style::new().bold();
        println!(
            "{} {} ({} / {})",
            bold.apply_to("Watching:"),
            session_id,
            provider_str(&detail.session.provider),
            work_status_str(&detail.session.work_status)
        );
        let mut seen_row_ids = HashSet::new();
        print_conversation_snapshot_rows(&conversation, &mut seen_row_ids);
        println!("Press Ctrl+C to stop.\n");
    }

    // Default: no timeout (wait indefinitely until session ends or Ctrl+C)
    let timeout = timeout_secs
        .map(Duration::from_secs)
        .unwrap_or(Duration::from_secs(u64::MAX / 2));

    loop {
        match ws.recv_timeout(timeout).await {
            Ok(Some(ref msg)) => {
                if !filter.is_empty() {
                    let event_type = event_type_name(msg);
                    if !filter.iter().any(|f| event_type.contains(f.as_str())) {
                        continue;
                    }
                }

                if output.json {
                    output.print_json(msg);
                } else {
                    print_watch_event(msg);
                }

                if matches!(msg, ServerMessage::SessionEnded { .. }) {
                    return EXIT_SUCCESS;
                }
            }
            Ok(None) => {
                if !output.json {
                    println!("\nConnection closed.");
                }
                return EXIT_SUCCESS;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

async fn rename(config: &ClientConfig, output: &Output, session_id: &str, name: &str) -> i32 {
    let Some(mut ws) = ws_connect(config, output).await else {
        return EXIT_CONNECTION_ERROR;
    };

    if let Err(e) = ws
        .send(&ClientMessage::RenameSession {
            session_id: session_id.to_string(),
            name: Some(name.to_string()),
        })
        .await
    {
        output.print_error(&CliError::connection(e.to_string()));
        return EXIT_CONNECTION_ERROR;
    }

    match ws.recv_timeout(Duration::from_secs(5)).await {
        Ok(Some(ServerMessage::Error { code, message, .. })) => {
            output.print_error(&CliError::new(code, message));
            return EXIT_SERVER_ERROR;
        }
        Err(e) => {
            output.print_error(&CliError::connection(e.to_string()));
            return EXIT_CONNECTION_ERROR;
        }
        _ => {}
    }

    if output.json {
        output.print_json(&serde_json::json!({"renamed": true, "name": name}));
    } else {
        println!("Session renamed to: {name}");
    }
    EXIT_SUCCESS
}

async fn resume(rest: &RestClient, output: &Output, session_id: &str) -> i32 {
    match rest
        .post_json::<_, ResumeSessionResponse>(
            &format!("/api/sessions/{session_id}/resume"),
            &serde_json::json!({}),
        )
        .await
        .into_result()
    {
        Ok(resp) => {
            let session = resp.session;
            if output.json {
                output.print_json(&serde_json::json!({
                    "resumed": true,
                    "session_id": session.id,
                    "work_status": work_status_str(&session.work_status),
                }));
            } else {
                println!(
                    "Session resumed. Status: {}",
                    work_status_str(&session.work_status)
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

// ── Streaming Helpers ────────────────────────────────────────

async fn stream_turn_events(ws: &mut WsClient, output: &Output) -> i32 {
    let timeout = Duration::from_secs(300);
    let mut saw_turn_activity = false;

    loop {
        match ws.recv_timeout(timeout).await {
            Ok(Some(ref msg)) => {
                if output.json {
                    output.print_json(msg);
                }
                match msg {
                    ServerMessage::ConversationRowsChanged { upserted, .. } => {
                        if !upserted.is_empty() {
                            saw_turn_activity = true;
                        }
                        if !output.json {
                            for entry in upserted {
                                let role = format_row_type_summary(&entry.row);
                                let content = extract_row_content_str_summary(&entry.row);
                                if !content.is_empty() {
                                    println!("[{role}] {content}");
                                }
                            }
                        }
                    }
                    ServerMessage::SessionDelta { changes, .. } => {
                        if changes.work_status.is_some() || changes.last_message.is_some() {
                            saw_turn_activity = true;
                        }
                        if !output.json {
                            let dim = console::Style::new().dim();
                            if let Some(status) = &changes.work_status {
                                println!(
                                    "{} work_status -> {}",
                                    dim.apply_to("delta"),
                                    work_status_str(status)
                                );
                                if stream_turn_should_exit(status, saw_turn_activity) {
                                    return EXIT_SUCCESS;
                                }
                            }
                            if let Some(Some(name)) = &changes.custom_name {
                                println!("{} name -> {name}", dim.apply_to("delta"));
                            }
                            if let Some(Some(summary)) = &changes.summary {
                                println!("{} summary -> {summary}", dim.apply_to("delta"));
                            }
                        } else if let Some(status) = &changes.work_status {
                            if stream_turn_should_exit(status, saw_turn_activity) {
                                return EXIT_SUCCESS;
                            }
                        }
                    }
                    ServerMessage::ApprovalRequested { request, .. } => {
                        if !output.json {
                            let tool = request.tool_name.as_deref().unwrap_or("unknown");
                            let preview = request
                                .command
                                .as_deref()
                                .or(request.tool_input.as_deref())
                                .unwrap_or("(see request)");
                            println!("\nApproval needed: {tool} — {preview}");
                        }
                        return EXIT_SUCCESS;
                    }
                    ServerMessage::SessionEnded { reason, .. } => {
                        if !output.json {
                            println!("Session ended: {reason}");
                        }
                        return EXIT_SUCCESS;
                    }
                    ServerMessage::Error { code, message, .. } => {
                        output.print_error(&CliError::new(code.clone(), message.clone()));
                        return EXIT_SERVER_ERROR;
                    }
                    _ => {}
                }
            }
            Ok(None) => {
                if !output.json {
                    eprintln!("Connection closed or timed out.");
                }
                return EXIT_CONNECTION_ERROR;
            }
            Err(e) => {
                output.print_error(&CliError::connection(e.to_string()));
                return EXIT_CONNECTION_ERROR;
            }
        }
    }
}

fn format_row_type_summary(
    row: &orbitdock_protocol::conversation_contracts::ConversationRowSummary,
) -> &'static str {
    use orbitdock_protocol::conversation_contracts::ConversationRowSummary;
    match row {
        ConversationRowSummary::User(_) => "user",
        ConversationRowSummary::Assistant(_) => "assistant",
        ConversationRowSummary::Tool(_) => "tool",
        ConversationRowSummary::Thinking(_) => "thinking",
        ConversationRowSummary::System(_) => "system",
        ConversationRowSummary::Worker(_) => "worker",
        ConversationRowSummary::Hook(_) => "hook",
        ConversationRowSummary::Plan(_) => "plan",
        _ => "other",
    }
}

fn event_type_name(msg: &ServerMessage) -> &'static str {
    match msg {
        ServerMessage::Hello { .. } => "hello",
        ServerMessage::SessionDelta { .. } => "session_delta",
        ServerMessage::ConversationRowsChanged { .. } => "conversation_rows_changed",
        ServerMessage::ApprovalRequested { .. } => "approval_requested",
        ServerMessage::ApprovalDecisionResult { .. } => "approval_decision_result",
        ServerMessage::ApprovalDeleted { .. } => "approval_deleted",
        ServerMessage::ApprovalsList { .. } => "approvals_list",
        ServerMessage::TokensUpdated { .. } => "tokens_updated",
        ServerMessage::SessionEnded { .. } => "session_ended",
        ServerMessage::SessionForked { .. } => "session_forked",
        ServerMessage::ContextCompacted { .. } => "context_compacted",
        ServerMessage::UndoStarted { .. } => "undo_started",
        ServerMessage::UndoCompleted { .. } => "undo_completed",
        ServerMessage::ThreadRolledBack { .. } => "thread_rolled_back",
        ServerMessage::ShellStarted { .. } => "shell_started",
        ServerMessage::ShellOutput { .. } => "shell_output",
        ServerMessage::TurnDiffSnapshot { .. } => "turn_diff_snapshot",
        ServerMessage::RateLimitEvent { .. } => "rate_limit_event",
        ServerMessage::PromptSuggestion { .. } => "prompt_suggestion",
        ServerMessage::Error { .. } => "error",
        ServerMessage::ServerInfo { .. } => "server_info",
        ServerMessage::ModelsList { .. } => "models_list",
        ServerMessage::ReviewCommentCreated { .. } => "review_comment_created",
        ServerMessage::ReviewCommentUpdated { .. } => "review_comment_updated",
        ServerMessage::ReviewCommentDeleted { .. } => "review_comment_deleted",
        ServerMessage::ReviewCommentsList { .. } => "review_comments_list",
        ServerMessage::WorktreeCreated { .. } => "worktree_created",
        ServerMessage::WorktreeRemoved { .. } => "worktree_removed",
        ServerMessage::WorktreeStatusChanged { .. } => "worktree_status_changed",
        ServerMessage::WorktreeError { .. } => "worktree_error",
        ServerMessage::WorktreesList { .. } => "worktrees_list",
        ServerMessage::CodexAccountStatus { .. } => "codex_account_status",
        ServerMessage::CodexAccountUpdated { .. } => "codex_account_updated",
        ServerMessage::CodexLoginChatgptStarted { .. } => "codex_login_started",
        ServerMessage::CodexLoginChatgptCompleted { .. } => "codex_login_completed",
        ServerMessage::CodexLoginChatgptCanceled { .. } => "codex_login_canceled",
        ServerMessage::ClaudeCapabilities { .. } => "claude_capabilities",
        ServerMessage::ClaudeUsageResult { .. } => "claude_usage_result",
        ServerMessage::CodexUsageResult { .. } => "codex_usage_result",
        ServerMessage::FilesPersisted { .. } => "files_persisted",
        ServerMessage::McpToolsList { .. } => "mcp_tools_list",
        ServerMessage::McpStartupUpdate { .. } => "mcp_startup_update",
        ServerMessage::McpStartupComplete { .. } => "mcp_startup_complete",
        ServerMessage::SkillsList { .. } => "skills_list",
        ServerMessage::SkillsUpdateAvailable { .. } => "skills_update_available",
        ServerMessage::SubagentToolsList { .. } => "subagent_tools_list",
        ServerMessage::OpenAiKeyStatus { .. } => "openai_key_status",
        ServerMessage::DirectoryListing { .. } => "directory_listing",
        ServerMessage::RecentProjectsList { .. } => "recent_projects_list",
        ServerMessage::PermissionRules { .. } => "permission_rules",
        ServerMessage::DashboardInvalidated { .. } => "dashboard_invalidated",
        ServerMessage::MissionsInvalidated { .. } => "missions_invalidated",
        ServerMessage::MissionsList { .. } => "missions_list",
        ServerMessage::MissionDelta { .. } => "mission_delta",
        ServerMessage::MissionHeartbeat { .. } => "mission_heartbeat",
        ServerMessage::SteerOutcome { .. } => "steer_outcome",
    }
}

fn print_watch_event(msg: &ServerMessage) {
    let dim = console::Style::new().dim();
    let bold = console::Style::new().bold();

    match msg {
        ServerMessage::Hello { hello } => {
            println!(
                "{} compatibility {} [{}] ({})",
                dim.apply_to("hello"),
                if hello.compatibility.compatible {
                    "compatible"
                } else {
                    "incompatible"
                },
                hello.compatibility.server_compatibility,
                hello.server_version
            );
        }
        ServerMessage::SessionDelta { changes, .. } => {
            if let Some(status) = &changes.work_status {
                println!(
                    "{} work_status -> {}",
                    dim.apply_to("delta"),
                    work_status_str(status)
                );
            }
            if let Some(Some(name)) = &changes.custom_name {
                println!("{} name -> {name}", dim.apply_to("delta"));
            }
            if let Some(Some(summary)) = &changes.summary {
                println!("{} summary -> {summary}", dim.apply_to("delta"));
            }
        }
        ServerMessage::ConversationRowsChanged { upserted, .. } => {
            for entry in upserted {
                let role = format_row_type_summary(&entry.row);
                let content = extract_row_content_str_summary(&entry.row);
                let content = truncate(&content, 120);
                println!("{} [{role}] {content}", bold.apply_to("+row"));
            }
        }
        ServerMessage::ApprovalRequested { request, .. } => {
            let coral = console::Style::new().red().bold();
            println!(
                "{} {} — {}",
                coral.apply_to("approval"),
                request.tool_name.as_deref().unwrap_or("unknown"),
                request.id
            );
        }
        ServerMessage::ApprovalDecisionResult {
            outcome,
            request_id,
            ..
        } => {
            println!("{} {outcome} ({request_id})", dim.apply_to("decision"));
        }
        ServerMessage::TokensUpdated { usage, .. } => {
            let fill = usage.context_fill_percent();
            println!(
                "{} {fill:.0}% ({} in / {} out)",
                dim.apply_to("tokens"),
                usage.input_tokens,
                usage.output_tokens
            );
        }
        ServerMessage::SessionEnded { reason, .. } => {
            println!("{} {reason}", bold.apply_to("ended"));
        }
        ServerMessage::ContextCompacted { .. } => {
            println!("{}", dim.apply_to("context compacted"));
        }
        ServerMessage::UndoCompleted { success, .. } => {
            println!("{} success={success}", dim.apply_to("undo"));
        }
        ServerMessage::ShellStarted { command, .. } => {
            println!("{} {command}", bold.apply_to("shell"));
        }
        ServerMessage::ShellOutput {
            stdout,
            stderr,
            exit_code,
            ..
        } => {
            if !stdout.is_empty() {
                print!("{stdout}");
            }
            if !stderr.is_empty() {
                eprint!("{stderr}");
            }
            if let Some(code) = exit_code {
                println!("{} exit {code}", dim.apply_to("shell"));
            }
        }
        ServerMessage::Error { code, message, .. } => {
            let red = console::Style::new().red();
            println!("{} [{code}] {message}", red.apply_to("error"));
        }
        _ => {
            println!("{} {}", dim.apply_to("event"), event_type_name(msg));
        }
    }
}

fn print_conversation_snapshot_rows(
    snapshot: &ConversationSnapshotPage,
    seen_row_ids: &mut HashSet<String>,
) {
    for entry in &snapshot.rows {
        if !seen_row_ids.insert(entry.id().to_string()) {
            continue;
        }
        let role = format_row_type_summary(&entry.row);
        let content = truncate(&extract_row_content_str_summary(&entry.row), 120);
        if !content.is_empty() {
            println!("[{role}] {content}");
        }
    }
}

// ── Human Output ─────────────────────────────────────────────

fn print_session_detail(session: &SessionState, show_messages: bool) {
    let bold = console::Style::new().bold();

    println!("{} {}", bold.apply_to("Session:"), session.id);
    println!(
        "{} {}",
        bold.apply_to("Provider:"),
        provider_str(&session.provider)
    );
    println!("{} {}", bold.apply_to("Project:"), session.project_path);
    println!(
        "{} {} / {}",
        bold.apply_to("Status:"),
        session_status_str(&session.status),
        work_status_str(&session.work_status)
    );

    if let Some(ref model) = session.model {
        println!("{} {}", bold.apply_to("Model:"), model);
    }
    if let Some(ref name) = session.custom_name {
        println!("{} {}", bold.apply_to("Name:"), name);
    }
    if let Some(ref summary) = session.summary {
        println!("{} {}", bold.apply_to("Summary:"), summary);
    }
    if let Some(ref branch) = session.git_branch {
        println!("{} {}", bold.apply_to("Branch:"), branch);
    }

    let usage = &session.token_usage;
    if usage.context_window > 0 {
        let fill = usage.context_fill_percent();
        println!(
            "{} {:.0}% ({} in / {} out / {} cached / {} window)",
            bold.apply_to("Context:"),
            fill,
            usage.input_tokens,
            usage.output_tokens,
            usage.cached_tokens,
            usage.context_window,
        );
    }

    // Messages are now delivered via ConversationRowPage, not inline on SessionState.
    // The CLI `session get -m` flag should use the conversation history endpoint.
    let _ = show_messages;
}

#[cfg(test)]
mod tests {
    use super::stream_turn_should_exit;
    use orbitdock_protocol::WorkStatus;

    #[test]
    fn stream_turn_waiting_requires_real_turn_activity() {
        assert!(!stream_turn_should_exit(&WorkStatus::Waiting, false));
        assert!(stream_turn_should_exit(&WorkStatus::Waiting, true));
    }

    #[test]
    fn stream_turn_exit_rules_match_user_visible_completion() {
        assert!(!stream_turn_should_exit(&WorkStatus::Working, true));
        assert!(stream_turn_should_exit(&WorkStatus::Permission, true));
        assert!(stream_turn_should_exit(&WorkStatus::Reply, true));
        assert!(stream_turn_should_exit(&WorkStatus::Ended, true));
    }
}
