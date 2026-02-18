# Contributing

## Prerequisites

- Windows PowerShell 5.1+ (or PowerShell 7)
- Git
- Pester module
- PSScriptAnalyzer module

Install tooling:

```powershell
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module Pester -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

## Development Workflow

1. Create a branch from `main`.
2. Make focused changes.
3. Run lint and tests locally.
4. Open a pull request.

## Git Hooks (Husky-style)

This repo uses `.husky/` hooks via `core.hooksPath`:

- `pre-commit`: blocks `docs/` commits and runs PSScriptAnalyzer on staged PowerShell files.
- `pre-push`: blocks pushes containing `docs/` changes, runs full lint checks, then runs Pester tests.

If checks fail, commit/push is blocked.

## Local Validation

Run lint:

```powershell
Invoke-ScriptAnalyzer -Path .\collect-endpoint-evidence.ps1, .\src, .\tests\pester -Recurse
```

Run tests:

```powershell
.\tests\pester\Invoke-Pester.ps1
```

Run CI-style tests with XML output:

```powershell
.\tests\pester\Invoke-Pester.ps1 -CI
```

## Security Expectations

- Do not add logic that exports unredacted secrets.
- Preserve fail-closed behavior for redaction failures.
- Keep `docs/` local-only and uncommitted.
