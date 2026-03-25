# Server-Authoritative Session Contract

> Goal: finish the projection-first rewrite so the Rust server owns durable session truth, HTTP owns initial and heavy reads, and WebSocket owns realtime deltas plus replay.
>
> Status: Active
>
> Last updated: 2026-03-25 (legacy snapshot transport removed)

## Invariants

- The Rust server is the only authority for `control_mode`, `lifecycle_state`, and `accepts_user_input`.
- HTTP owns initial dashboard, mission, detail, composer, and conversation reads.
- WebSocket owns realtime deltas and replay only.
- The client never derives business truth from runtime connector maps, mixed bootstrap paths, or synthetic catch-all render state.

## Workstreams

### Worker 1 — Server Authority Model

Status: Done
Owner: Codex worker A
Blocking dependency: None

- [x] Add `control_mode` to persisted session state and backfill old rows.
- [x] Centralize create, takeover, resume, attach, detach, and end transitions.
- [x] Make startup restore downgrade failed direct/open resumes to resumable instead of dropping sessions.
- [x] Make failed send enqueue create no ghost accepted row.

### Worker 2 — Server Transport and Replay

Status: Done
Owner: Codex worker B
Blocking dependency: None

- [x] Make dashboard, missions, and session surfaces HTTP-first and WS-delta-only.
- [x] Honor `since_revision` on subscriptions.
- [x] Add explicit replay-gap fallback to HTTP snapshot.
- [x] Remove fake empty mission bootstrap behavior.

### Worker 3 — Swift Dashboard and Mission Bootstrap

Status: Done
Owner: Codex main
Blocking dependency: Worker 2 for final delta shape

- [x] Remove dual dashboard bootstrap.
- [x] Make dashboard initial load use `GET /api/dashboard`.
- [x] Subscribe to dashboard deltas only after storing the HTTP snapshot revision.
- [x] Remove direct reads of registry aggregate arrays outside the shared dashboard projection store.

### Worker 4 — Swift Session Surfaces

Status: Done
Owner: Codex main
Blocking dependency: Worker 2 for final surface replay contract

- [x] Load detail, composer, and conversation from their HTTP snapshot endpoints.
- [x] Subscribe each surface explicitly and unsubscribe each surface explicitly.
- [x] Remove store-layer synthetic render snapshots.
- [x] Make mutation responses authoritative and let subscriptions reconcile afterward.

### Worker 5 — Tests, Docs, and Cleanup

Status: In progress
Owner: Codex main
Blocking dependency: Workers 1-4 merged

- [x] Update `docs/data-flow.md`.
- [x] Update `docs/client-networking.md`.
- [x] Remove legacy bootstrap and fallback code paths.
- [x] Make CLI bootstrap/create/resume/watch HTTP-first and WS-realtime-only.
- [x] Run CI validation.
- [ ] Run manual perf smoke validation.

## Merge Order

1. Worker 1 and Worker 2 start in parallel.
2. Worker 3 starts dashboard cleanup immediately, then rebases once Worker 2 lands.
3. Worker 4 starts after Worker 2 stabilizes the surface replay contract.
4. Worker 5 lands after the four implementation workstreams merge.

## Definition Of Done

- [x] No dual dashboard bootstrap remains.
- [x] `control_mode` and `lifecycle_state` are durable server-owned state.
- [x] All session surfaces use HTTP snapshot + WS replayable delta.
- [x] `since_revision` is honored everywhere it exists in the protocol.
- [x] Failed send creates no conversation row.
- [x] Failed direct restore never drops the session.
- [x] Docs and tests match the shipped contract.

## Validation Notes

- `make rust-ci` passes.
- `make build` passes.
- `make test-unit` passes.
- `cargo check -p orbitdock` passes.
- `transport/websocket/` no longer emits dashboard, missions, detail, composer, or conversation snapshot messages; replay gaps now ask clients to refetch the matching HTTP surface.
- WebSocket session create/resume/fork lifecycle bootstrap handlers have been removed in favor of REST-only bootstrap and mutation flows.
- The old subscribe-time snapshot fallback shape and heavy conversation all-rows websocket resync path have been removed.
- Manual perf smoke with a many-active-agents scenario is still the one remaining real-world validation step.
