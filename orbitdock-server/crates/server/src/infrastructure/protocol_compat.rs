use axum::{
    body::Body,
    http::{HeaderMap, Request, Response, StatusCode},
    middleware::Next,
};
use orbitdock_protocol::{
    CompatibilityStatus, HTTP_HEADER_CLIENT_COMPATIBILITY, HTTP_HEADER_CLIENT_VERSION,
    HTTP_HEADER_COMPATIBILITY_MESSAGE, HTTP_HEADER_COMPATIBILITY_REASON, HTTP_HEADER_COMPATIBLE,
    HTTP_HEADER_SERVER_COMPATIBILITY, HTTP_HEADER_SERVER_VERSION, SERVER_COMPATIBILITY,
};
use tracing::{info, warn};

use crate::VERSION;

pub(crate) fn compatibility_status_from_headers(headers: &HeaderMap) -> CompatibilityStatus {
    let client_compatibility = header_value(headers, HTTP_HEADER_CLIENT_COMPATIBILITY);
    let client_version = header_value(headers, HTTP_HEADER_CLIENT_VERSION);

    if client_compatibility.as_deref() == Some(SERVER_COMPATIBILITY) {
        return CompatibilityStatus {
            compatible: true,
            server_compatibility: SERVER_COMPATIBILITY.to_string(),
            reason: None,
            message: None,
        };
    }

    let reason = classify_reason(client_version.as_deref());
    CompatibilityStatus {
        compatible: false,
        server_compatibility: SERVER_COMPATIBILITY.to_string(),
        reason: Some(reason.to_string()),
        message: Some(compatibility_message(reason, client_version.as_deref())),
    }
}

pub(crate) fn compatibility_status_for_request(request: &Request<Body>) -> CompatibilityStatus {
    compatibility_status_from_headers(request.headers())
}

fn attach_headers(response: &mut Response<Body>, compatibility: &CompatibilityStatus) {
    response.headers_mut().insert(
        HTTP_HEADER_SERVER_VERSION,
        VERSION.parse().expect("valid server version header"),
    );
    response.headers_mut().insert(
        HTTP_HEADER_SERVER_COMPATIBILITY,
        compatibility
            .server_compatibility
            .parse()
            .expect("valid server compatibility header"),
    );
    response.headers_mut().insert(
        HTTP_HEADER_COMPATIBLE,
        if compatibility.compatible {
            "true"
        } else {
            "false"
        }
        .parse()
        .expect("valid compatibility header"),
    );

    if let Some(reason) = &compatibility.reason {
        response.headers_mut().insert(
            HTTP_HEADER_COMPATIBILITY_REASON,
            reason.parse().expect("valid compatibility reason header"),
        );
    }
    if let Some(message) = &compatibility.message {
        response.headers_mut().insert(
            HTTP_HEADER_COMPATIBILITY_MESSAGE,
            message.parse().expect("valid compatibility message header"),
        );
    }
}

pub(crate) async fn compatibility_middleware(req: Request<Body>, next: Next) -> Response<Body> {
    let path = req.uri().path().to_string();

    // Only enforce the compatibility gate on protocol endpoints (WebSocket + API).
    // Health, metrics, and web UI assets are not protocol clients.
    let is_protocol_route = path == "/ws" || path.starts_with("/api/");
    if !is_protocol_route {
        return next.run(req).await;
    }

    let compatibility = compatibility_status_for_request(&req);
    if path == "/ws" {
        info!(
            component = "protocol_compat",
            event = "protocol_compat.request",
            path = %path,
            client_version = ?header_value(req.headers(), HTTP_HEADER_CLIENT_VERSION),
            client_compatibility = ?header_value(req.headers(), HTTP_HEADER_CLIENT_COMPATIBILITY),
            has_authorization = req.headers().contains_key("authorization"),
            has_token_query = req.uri().query().map(|query| query.contains("token=")).unwrap_or(false),
            compatible = compatibility.compatible,
            reason = ?compatibility.reason,
            "Checked client compatibility headers"
        );
    }
    if !compatibility.compatible {
        if path == "/ws" {
            warn!(
                component = "protocol_compat",
                event = "protocol_compat.rejected",
                path = %path,
                client_version = ?header_value(req.headers(), HTTP_HEADER_CLIENT_VERSION),
                client_compatibility = ?header_value(req.headers(), HTTP_HEADER_CLIENT_COMPATIBILITY),
                has_authorization = req.headers().contains_key("authorization"),
                has_token_query = req.uri().query().map(|query| query.contains("token=")).unwrap_or(false),
                reason = ?compatibility.reason,
                message = ?compatibility.message,
                "Rejected incompatible client request"
            );
        }
        let mut response = Response::builder()
            .status(StatusCode::UPGRADE_REQUIRED)
            .header("content-type", "application/json")
            .body(Body::from(format!(
                "{{\"code\":\"incompatible_client\",\"error\":\"{}\"}}",
                compatibility
                    .message
                    .as_deref()
                    .unwrap_or("Client is not compatible with this server build.")
            )))
            .expect("valid upgrade required response");
        attach_headers(&mut response, &compatibility);
        return response;
    }

    let mut response = next.run(req).await;
    attach_headers(&mut response, &compatibility);
    response
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_string())
}

fn classify_reason(client_version: Option<&str>) -> &'static str {
    match compare_versions(client_version, Some(VERSION)) {
        Some(std::cmp::Ordering::Less) => "upgrade_app",
        Some(std::cmp::Ordering::Greater) => "upgrade_server",
        _ => "unsupported_client",
    }
}

fn compatibility_message(reason: &str, client_version: Option<&str>) -> String {
    match reason {
        "upgrade_app" => format!(
            "Update OrbitDock to a build compatible with server {}.",
            VERSION
        ),
        "upgrade_server" => match client_version {
            Some(version) if !version.is_empty() => format!(
                "Update the OrbitDock server to work with client {}.",
                version
            ),
            _ => "Update the OrbitDock server to match this client.".to_string(),
        },
        _ => format!(
            "This client is not compatible with server {} (expects {}).",
            VERSION, SERVER_COMPATIBILITY
        ),
    }
}

fn compare_versions(left: Option<&str>, right: Option<&str>) -> Option<std::cmp::Ordering> {
    let left = parse_version(left?)?;
    let right = parse_version(right?)?;
    Some(left.cmp(&right))
}

fn parse_version(value: &str) -> Option<(u64, u64, u64)> {
    let mut parts = value.trim().split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next().unwrap_or("0").parse().ok()?;
    let patch = parts.next().unwrap_or("0").parse().ok()?;
    Some((major, minor, patch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compatibility_status_accepts_matching_contract() {
        let mut headers = HeaderMap::new();
        headers.insert(
            HTTP_HEADER_CLIENT_COMPATIBILITY,
            SERVER_COMPATIBILITY.parse().unwrap(),
        );
        headers.insert(HTTP_HEADER_CLIENT_VERSION, "0.4.0".parse().unwrap());

        let status = compatibility_status_from_headers(&headers);

        assert!(status.compatible);
        assert_eq!(status.server_compatibility, SERVER_COMPATIBILITY);
        assert_eq!(status.reason, None);
        assert_eq!(status.message, None);
    }

    #[test]
    fn compatibility_status_requests_app_upgrade_for_older_client() {
        let mut headers = HeaderMap::new();
        headers.insert(
            HTTP_HEADER_CLIENT_COMPATIBILITY,
            "legacy_contract".parse().unwrap(),
        );
        headers.insert(HTTP_HEADER_CLIENT_VERSION, "0.3.0".parse().unwrap());

        let status = compatibility_status_from_headers(&headers);

        assert!(!status.compatible);
        assert_eq!(status.reason.as_deref(), Some("upgrade_app"));
    }
}
