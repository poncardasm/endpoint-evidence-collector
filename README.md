# Endpoint Evidence Collector

Windows-first endpoint diagnostics collector for service desk escalation workflows.

## Summary

This tool helps IT support / Service Desk to staff quickly gather the right troubleshooting information from a computer when an issue needs to be escalated.  

In one run, it collects:
- basic computer and Windows details,
- running apps and background processes,
- disk space/health information,
- network and DNS settings plus basic connectivity checks,
- installed applications,
- and recent system/application event logs.

It then hides sensitive details and produces a clean evidence package that can be safely shared with advanced support teams.

## Status

- Current state: `v1.0` implementation complete per `docs/TASKS.md` checklist.
- Core features: implemented and integrated (collection, redaction, packaging, integrity, retention, CI/testing, docs/examples).
- Post-v1 scaffolds: added for Python wrapper, macOS collectors, ticketing adapters, and upload automation.

## Problem

Escalation evidence is often inconsistent, incomplete, and manually assembled. This project standardizes collection and redaction into a single run.

## Users

- L1/L2 IT support technicians
- Escalation managers and incident responders

## Features

- Single command evidence collection via `collect-endpoint-evidence.ps1`
- Standardized JSON + Markdown outputs per run
- Sensitive data redaction before export artifacts are created
- Timestamped bundle generation with checksum and optional signature/encryption
- Retention cleanup controls for aged run directories
- CI quality gates with lint, tests, secret scanning, and dependency review

## Architecture

- `collect-endpoint-evidence.ps1`: entry point and CLI validation
- `src/EndpointEvidenceCollector/EndpointEvidenceCollector.psm1`: collectors, redaction, packaging, integrity, retention, and run orchestration
- `src/EndpointEvidenceCollector/EndpointEvidenceCollector.psd1`: module manifest and exports
- `src/collectors/macos/Get-EecMacOSEvidence.ps1`: post-v1 macOS collector scaffold
- `src/integrations/ticketing/adapter.ps1`: post-v1 ticketing adapter stubs
- `src/integrations/upload/Upload-EecBundle.ps1`: post-v1 upload automation stub
- `wrapper/python/eec_wrapper.py`: post-v1 Typer orchestration wrapper
- `tests/pester`: unit/integration tests and CI test runner
- `.github/workflows/ci.yml`: lint, tests, secret scan, dependency review

Collection pipeline:
1. Validate parameters and build collector plan.
2. Collect raw evidence by category.
3. Redact sensitive data (fail-closed on redaction errors).
4. Write artifacts (`*.json`, `summary.md`, `manifest.json`, `redaction-report.json`).
5. Build bundle (`.zip` or encrypted `.enc`) and checksum/signature artifacts.
6. Apply retention cleanup.

## Setup

### Prerequisites

- Windows PowerShell 5.1+ (PowerShell 7 compatible target)
- Optional for testing: `Pester`, `PSScriptAnalyzer`

### Quick start

```powershell
.\collect-endpoint-evidence.ps1 -DryRun
```

## Usage

### Normal run

```powershell
.\collect-endpoint-evidence.ps1 `
  -CaseId "INC-10492" `
  -OutputDir ".\\out" `
  -RedactionLevel "standard" `
  -Include "system","processes","disk","network","apps","eventlogs"
```

### Dry-run plan only

```powershell
.\collect-endpoint-evidence.ps1 `
  -DryRun `
  -OutputDir ".\\out" `
  -Include "system","network"
```

### Strict redaction and encrypted bundle

```powershell
$pw = Read-Host "Bundle password" -AsSecureString
.\collect-endpoint-evidence.ps1 `
  -CaseId "INC-10492" `
  -RedactionLevel "strict" `
  -EnableBundleEncryption `
  -BundlePassword $pw
```

### Detached signature output

```powershell
.\collect-endpoint-evidence.ps1 `
  -CaseId "INC-10492" `
  -EnableSignature `
  -SigningCertThumbprint "0123456789ABCDEF0123456789ABCDEF01234567"
```

### Retention cleanup only

```powershell
.\collect-endpoint-evidence.ps1 `
  -OutputDir ".\\out" `
  -RetentionDays 7 `
  -RetentionCleanupOnly
```

## Output Artifacts

Each run directory contains:

- `summary.md`
- `manifest.json`
- `redaction-report.json`
- `<collector>.json` files (`system.json`, `network.json`, etc.)
- bundle file (`*.zip` or `*.enc`)
- `bundle.sha256`
- `checksum-verify.txt`
- optional `*.sig.json` (when signature is enabled)

See sample sanitized structure: `examples/sanitized-bundle/`.

## Integrity Verification

From a run directory:

```powershell
$expected = (Get-Content .\bundle.sha256).Split('  ')[0]
$bundle = (Get-Content .\bundle.sha256).Split('  ')[1]
$actual = (Get-FileHash -Algorithm SHA256 (Join-Path . $bundle)).Hash.ToLower()
if ($expected -eq $actual) { "Checksum OK" } else { "Checksum MISMATCH" }
```

## Security Handling

- Redaction is required before final export artifacts.
- If redaction errors occur, export artifacts are blocked (fail-closed).
- Share bundles only through approved organizational channels.
- Use retention policy controls (`-RetentionDays`, `-RetentionCleanupOnly`).
- Optional controls:
  - `-EnableBundleEncryption -BundlePassword <SecureString>` for encrypted output.
  - `-EnableSignature -SigningCertThumbprint <thumbprint>` for detached signature output.

## Local Development and Tests

Run tests locally:

```powershell
# from repo root
.\tests\pester\Invoke-Pester.ps1
```

Run lint locally:

```powershell
Invoke-ScriptAnalyzer -Path .\collect-endpoint-evidence.ps1, .\src, .\tests\pester -Recurse
```

## Pilot and Release Readiness

Pilot execution assets:

- `pilot/PILOT_EXECUTION.md`
- `pilot/PILOT_RESULTS.md`
- `scripts/Measure-PilotResults.ps1`

Generate pilot metrics from run outputs:

```powershell
.\scripts\Measure-PilotResults.ps1 -OutputRoot .\out -ReportPath .\pilot\pilot-metrics-report.json
```

Release assets:

- `RELEASE_READINESS.md`
- `CHANGELOG.md`
- `RELEASE_NOTES_TEMPLATE.md`

## CI/CD Quality Gates

The CI workflow (`.github/workflows/ci.yml`) enforces:

- PowerShell static analysis via `PSScriptAnalyzer`
- Pester test execution with XML artifact upload
- Secret scanning (`gitleaks`)
- Dependency vulnerability review on PRs when dependency manifests are present

## Post-v1 Backlog

Scaffolded backlog items are documented in `POST_V1_BACKLOG.md`:

- Python Typer wrapper: `wrapper/python/eec_wrapper.py`
- macOS collectors scaffold: `src/collectors/macos/Get-EecMacOSEvidence.ps1`
- Ticketing adapter stubs: `src/integrations/ticketing/adapter.ps1`
- Upload automation stub: `src/integrations/upload/Upload-EecBundle.ps1`

## Troubleshooting

- Confirm PowerShell execution policy allows script execution.
- Run with `-DryRun` first to validate invocation.
- Review generated paths printed at the end of each run.
- For signature mode, verify the certificate exists in `CurrentUser\\My` or `LocalMachine\\My`.
