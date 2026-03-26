use orbitdock_protocol::{ClaudeModelOption, CodexModelOption};
use serde::{Deserialize, Serialize};

use crate::cli::{ModelAction, ProviderFilter};
use crate::client::rest::RestClient;
use crate::error::EXIT_SUCCESS;
use crate::output::Output;

#[derive(Debug, Deserialize, Serialize)]
struct CodexModelsResponse {
    models: Vec<CodexModelOption>,
}

#[derive(Debug, Deserialize, Serialize)]
struct ClaudeModelsResponse {
    models: Vec<ClaudeModelOption>,
}

#[derive(Debug, Serialize)]
struct ModelListSummary {
    provider: &'static str,
    count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    default_model_id: Option<String>,
}

#[derive(Debug, Serialize)]
struct ModelListJsonResponse {
    kind: &'static str,
    summaries: Vec<ModelListSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    codex: Option<Vec<CodexModelOption>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    claude: Option<Vec<ClaudeModelOption>>,
}

fn print_codex_models(models: &[CodexModelOption]) {
    println!("Codex Models ({}):", models.len());
    for m in models {
        let default_marker = if m.is_default { " (default)" } else { "" };
        println!("  {} - {}{}", m.id, m.display_name, default_marker);
        if !m.description.is_empty() {
            println!("    {}", m.description);
        }
    }
}

fn print_claude_models(models: &[ClaudeModelOption]) {
    println!("Claude Models ({}):", models.len());
    for m in models {
        println!("  {} - {}", m.value, m.display_name);
        if !m.description.is_empty() {
            println!("    {}", m.description);
        }
    }
}

fn build_codex_models_json_response(models: Vec<CodexModelOption>) -> ModelListJsonResponse {
    let default_model_id = models
        .iter()
        .find(|model| model.is_default)
        .map(|model| model.id.clone());
    ModelListJsonResponse {
        kind: "model_list",
        summaries: vec![ModelListSummary {
            provider: "codex",
            count: models.len(),
            default_model_id,
        }],
        codex: Some(models),
        claude: None,
    }
}

fn build_claude_models_json_response(models: Vec<ClaudeModelOption>) -> ModelListJsonResponse {
    ModelListJsonResponse {
        kind: "model_list",
        summaries: vec![ModelListSummary {
            provider: "claude",
            count: models.len(),
            default_model_id: None,
        }],
        codex: None,
        claude: Some(models),
    }
}

fn build_combined_models_json_response(
    codex: Vec<CodexModelOption>,
    claude: Vec<ClaudeModelOption>,
) -> ModelListJsonResponse {
    let codex_default = codex
        .iter()
        .find(|model| model.is_default)
        .map(|model| model.id.clone());
    ModelListJsonResponse {
        kind: "model_list",
        summaries: vec![
            ModelListSummary {
                provider: "codex",
                count: codex.len(),
                default_model_id: codex_default,
            },
            ModelListSummary {
                provider: "claude",
                count: claude.len(),
                default_model_id: None,
            },
        ],
        codex: Some(codex),
        claude: Some(claude),
    }
}

pub async fn run(action: &ModelAction, rest: &RestClient, output: &Output) -> i32 {
    match action {
        ModelAction::List { provider } => list(rest, output, provider.as_ref()).await,
    }
}

async fn list(rest: &RestClient, output: &Output, provider: Option<&ProviderFilter>) -> i32 {
    match provider {
        Some(ProviderFilter::Codex) => list_codex(rest, output).await,
        Some(ProviderFilter::Claude) => list_claude(rest, output).await,
        None => list_both(rest, output).await,
    }
}

async fn list_codex(rest: &RestClient, output: &Output) -> i32 {
    match rest
        .get::<CodexModelsResponse>("/api/models/codex")
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&build_codex_models_json_response(resp.models));
            } else {
                print_codex_models(&resp.models);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn list_claude(rest: &RestClient, output: &Output) -> i32 {
    match rest
        .get::<ClaudeModelsResponse>("/api/models/claude")
        .await
        .into_result()
    {
        Ok(resp) => {
            if output.json {
                output.print_json_pretty(&build_claude_models_json_response(resp.models));
            } else {
                print_claude_models(&resp.models);
            }
            EXIT_SUCCESS
        }
        Err((code, err)) => {
            output.print_error(&err);
            code
        }
    }
}

async fn list_both(rest: &RestClient, output: &Output) -> i32 {
    let (codex, claude) = tokio::join!(
        rest.get::<CodexModelsResponse>("/api/models/codex"),
        rest.get::<ClaudeModelsResponse>("/api/models/claude"),
    );

    let codex_models = match codex.into_result() {
        Ok(r) => r.models,
        Err((code, err)) => {
            output.print_error(&err);
            return code;
        }
    };

    let claude_models = match claude.into_result() {
        Ok(r) => r.models,
        Err((code, err)) => {
            output.print_error(&err);
            return code;
        }
    };

    if output.json {
        output.print_json_pretty(&build_combined_models_json_response(
            codex_models,
            claude_models,
        ));
    } else {
        print_codex_models(&codex_models);
        println!();
        print_claude_models(&claude_models);
    }
    EXIT_SUCCESS
}
