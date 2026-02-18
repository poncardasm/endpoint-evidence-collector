# Agent Instructions

## Project Context

- Project: `endpoint-evidence-collector`
- Purpose: Windows-first endpoint diagnostics collector for service desk escalations.
- Problem addressed: escalation evidence is often inconsistent, incomplete, and manually assembled.
- Primary users: L1/L2 IT support technicians, escalation managers, incident responders.
- Status: core `v1.0` implementation complete; post-v1 scaffolds are present.

## Current Capabilities

- Single-command collection via `collect-endpoint-evidence.ps1`.
- Windows collector set implemented: system, processes, disk, network, apps, event logs.
- Redaction pipeline implemented (`standard` and `strict`) with fail-closed export behavior.
- Artifact pipeline implemented: collector JSON files, `summary.md`, `manifest.json`, `redaction-report.json`, bundle, checksum, optional signature/encryption.
- Retention controls implemented: `-RetentionDays`, `-RetentionCleanupOnly`.
- CI quality gates implemented in `.github/workflows/ci.yml`.

## Repository Structure

- `collect-endpoint-evidence.ps1`: entry script and CLI validation.
- `src/EndpointEvidenceCollector/EndpointEvidenceCollector.psm1`: main module implementation.
- `src/EndpointEvidenceCollector/EndpointEvidenceCollector.psd1`: module manifest/exports.
- `tests/pester`: test suite and CI test runner.
- `examples/sanitized-bundle`: sample sanitized output structure.
- `pilot/` + `scripts/Measure-PilotResults.ps1`: pilot and release-readiness tooling.
- `wrapper/python` and `src/integrations/*`: post-v1 scaffolds.

## Working Rules

- Keep implementation aligned with `README.md` and `docs/PRD.md`.
- Prioritize PowerShell 5.1+ compatibility (PowerShell 7 compatible where possible).
- Prefer small, focused changes with clear command-line behavior.
- Preserve security posture: do not introduce flows that export unredacted sensitive data.
- Do not mark work as complete unless tests/validation assets are also updated where applicable.
- Maintain CI compatibility when changing scripts or test structure.

## Local-Only Docs Policy

- `docs/` is local-only working context.
- Never stage, commit, or push any file under `docs/`.
- You may read and edit files under `docs/` locally for planning/tracking.
- If `docs/` appears in staged changes, unstage it immediately.
