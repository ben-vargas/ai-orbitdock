use tokio::sync::oneshot;

use crate::runtime::session_actor::SessionActorHandle;
use crate::runtime::session_commands::{SessionCommand, SubscribeResult};

pub(crate) async fn request_subscribe(
  actor: &SessionActorHandle,
  since_revision: Option<u64>,
) -> Result<SubscribeResult, String> {
  let (sub_tx, sub_rx) = oneshot::channel();
  actor
    .send(SessionCommand::Subscribe {
      since_revision,
      reply: sub_tx,
    })
    .await;

  sub_rx.await.map_err(|error| error.to_string())
}
