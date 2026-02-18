# endpoint-evidence-collector

Windows-first endpoint diagnostics collector for service desk escalation workflows.

## Problem

Escalation evidence is often inconsistent, incomplete, and manually assembled. This project standardizes collection and redaction into a single run.

## Users

- L1/L2 IT support technicians
- Escalation managers and incident responders

## Features

- Single command evidence collection (planned)
- Standardized JSON + Markdown outputs (planned)
- Sensitive data redaction before export (planned)
- Timestamped ZIP bundle + checksum (planned)

## Architecture

- `collect-endpoint-evidence.ps1`: main entry script
- `src/collectors`: evidence collectors
- `src/redaction`: redaction pipeline
- `src/packaging`: manifest, checksum, archive
- `src/reporting`: summary output

## Setup

### Prerequisites

- Windows PowerShell 5.1+ (PowerShell 7 compatible target)

### Quick start

```powershell
.\collect-endpoint-evidence.ps1 -DryRun
```

## Usage

Example:

```powershell
.\collect-endpoint-evidence.ps1 `
  -CaseId "INC-10492" `
  -OutputDir ".\\out" `
  -RedactionLevel "standard" `
  -Include "system","processes","disk","network","apps","eventlogs"
```

## Security Handling

- Redaction is required before final export artifacts.
- Share bundles only through approved organizational channels.
- Retain bundles per policy and remove expired artifacts.
- Verify integrity using checksum (and signature when enabled).

## Troubleshooting

- Confirm PowerShell execution policy allows script execution.
- Run with `-DryRun` first to validate invocation.
- Review output and logs in `out/`.
