# Claude Code Instructions for OrbitDock

Shared repository guidance now lives in `AGENTS.md`.

Use [AGENTS.md](AGENTS.md) as the starting point for:
- day-to-day repo guardrails
- the docs map for workflow, architecture, debugging, and persistence
- the mutation-response rule: authoritative `POST`/`PATCH`/`PUT` responses should update local state immediately, then subscriptions reconcile
- links to the deeper docs in `docs/`

This file remains as a compatibility pointer for tools or workflows that still look for `CLAUDE.md`.
