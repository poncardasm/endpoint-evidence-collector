# Post-v1 Backlog

This file tracks scope intentionally deferred from v1.0.

## 1. Python Typer Wrapper

- Status: Scaffolded
- Location: `wrapper/python/eec_wrapper.py`
- Goal: Cross-platform orchestration parity for teams using Python tooling.

## 2. macOS Collectors

- Status: Scaffolded
- Location: `src/collectors/macos/Get-EecMacOSEvidence.ps1`
- Goal: Add macOS equivalents for system/process/disk/network evidence.

## 3. Ticketing Integrations

- Status: Stubbed
- Location: `src/integrations/ticketing/adapter.ps1`
- Goal: API adapters for ServiceNow, Jira, and Zendesk evidence attachments.

## 4. Upload Automation

- Status: Stubbed
- Location: `src/integrations/upload/Upload-EecBundle.ps1`
- Goal: Secure upload to approved storage/service endpoints with allowlist enforcement.

## Next Steps

1. Define auth model and secret management approach for adapters.
2. Add integration tests with mocked remote APIs.
3. Add config schema for per-environment endpoints and policy constraints.
4. Add CI jobs for post-v1 modules once implementation is active.
