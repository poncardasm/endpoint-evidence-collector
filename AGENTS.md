# Agent Instructions

## Project Context

- Project: `endpoint-evidence-collector`
- Purpose: Windows-first endpoint diagnostics collector for service desk escalations.
- Problem addressed: escalation evidence is often inconsistent, incomplete, and manually assembled.
- Primary users: L1/L2 IT support technicians, escalation managers, incident responders.

## Current Product Direction

- Single command evidence collection via `collect-endpoint-evidence.ps1`.
- Planned outputs: standardized JSON + Markdown summary.
- Planned packaging: timestamped ZIP bundle with checksum.
- Security expectation: redact sensitive data before final export.

## Repository Structure

- `collect-endpoint-evidence.ps1`: main entry script.
- `src/collectors`: endpoint evidence collectors.
- `src/redaction`: redaction pipeline.
- `src/packaging`: manifest, checksum, archive logic.
- `src/reporting`: human-readable summary/report generation.

## Working Rules

- Keep implementation aligned with `README.md` and `docs/PRD.md`.
- Prioritize PowerShell 5.1+ compatibility (PowerShell 7 compatible where possible).
- Prefer small, focused changes with clear command-line behavior.
- Preserve security posture: do not introduce flows that export unredacted sensitive data.

## Local-Only Docs Policy

- `docs/` is local-only working context.
- Never stage, commit, or push any file under `docs/`.
- You may read and edit files under `docs/` locally for planning/tracking.
- If `docs/` appears in staged changes, unstage it immediately.
