use axum::{
    body::Body,
    http::{Request, Response, StatusCode},
    middleware::Next,
};
use orbitdock_protocol::{
    HTTP_HEADER_CLIENT_PROTOCOL_MAJOR, HTTP_HEADER_PROTOCOL_MAJOR, HTTP_HEADER_PROTOCOL_MINOR,
    HTTP_HEADER_SERVER_VERSION, PROTOCOL_MAJOR, PROTOCOL_MINOR,
};

use crate::VERSION;

fn attach_headers(response: &mut Response<Body>) {
    response.headers_mut().insert(
        HTTP_HEADER_SERVER_VERSION,
        VERSION.parse().expect("valid server version header"),
    );
    response.headers_mut().insert(
        HTTP_HEADER_PROTOCOL_MAJOR,
        PROTOCOL_MAJOR
            .to_string()
            .parse()
            .expect("valid protocol major header"),
    );
    response.headers_mut().insert(
        HTTP_HEADER_PROTOCOL_MINOR,
        PROTOCOL_MINOR
            .to_string()
            .parse()
            .expect("valid protocol minor header"),
    );
}

pub(crate) fn client_protocol_major(request: &Request<Body>) -> Option<u16> {
    request
        .headers()
        .get(HTTP_HEADER_CLIENT_PROTOCOL_MAJOR)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u16>().ok())
}

pub(crate) async fn compatibility_middleware(req: Request<Body>, next: Next) -> Response<Body> {
    if let Some(client_major) = client_protocol_major(&req) {
        if client_major != PROTOCOL_MAJOR {
            let mut response = Response::builder()
                .status(StatusCode::UPGRADE_REQUIRED)
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    "{{\"code\":\"incompatible_client_protocol\",\"error\":\"Client protocol major {} is incompatible with server protocol major {}\"}}",
                    client_major, PROTOCOL_MAJOR
                )))
                .expect("valid upgrade required response");
            attach_headers(&mut response);
            return response;
        }
    }

    let mut response = next.run(req).await;
    attach_headers(&mut response);
    response
}
