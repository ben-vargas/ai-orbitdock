//! WebSocket transport sanitization helpers.

use orbitdock_protocol::ServerMessage;

/// Keep outbound frames within common client defaults (Apple URLSession WS default is 1 MiB).
pub(crate) const WS_MAX_TEXT_MESSAGE_BYTES: usize = 1024 * 1024;

/// Prepare an outbound `ServerMessage` for transport.
/// Never truncates content.
pub(crate) fn sanitize_server_message_for_transport(msg: ServerMessage) -> ServerMessage {
  msg
}

/// Sanitize a pre-serialized replay event JSON string for transport.
pub(crate) fn sanitize_replay_event_for_transport(event_json: &str) -> Option<String> {
  let mut value: serde_json::Value = serde_json::from_str(event_json).ok()?;
  let revision = value
    .as_object()
    .and_then(|object| object.get("revision").cloned());

  if let Some(object) = value.as_object_mut() {
    object.remove("revision");
  }

  let message: ServerMessage = serde_json::from_value(value).ok()?;
  let sanitized = sanitize_server_message_for_transport(message);
  let mut sanitized_value = serde_json::to_value(sanitized).ok()?;
  if let Some(revision) = revision {
    if let Some(object) = sanitized_value.as_object_mut() {
      object.insert("revision".to_string(), revision);
    }
  }

  serde_json::to_string(&sanitized_value).ok()
}

/// Check if any replay event exceeds the transport frame limit.
pub(crate) fn replay_has_oversize_event(events: &[String]) -> Option<usize> {
  events
    .iter()
    .map(String::len)
    .max()
    .filter(|size| *size > WS_MAX_TEXT_MESSAGE_BYTES)
}
