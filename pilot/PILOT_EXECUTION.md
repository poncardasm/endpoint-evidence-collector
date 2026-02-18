# Pilot Execution Plan

## Objective

Validate production readiness for `endpoint-evidence-collector` before v1.0 release.

## Pilot Scope

- Target group: 3-5 L1/L2 technicians.
- Duration: 1 week.
- Endpoint mix: at least 10 representative Windows endpoints.
- Workflow: run collector before escalation handoff.

## Success Criteria

- Median collection time < 5 minutes.
- No unredacted secret/token leakage in reviewed bundles.
- Stable execution with low critical failure count.
- Escalation teams accept bundle quality with minimal follow-up requests.

## Steps

1. Create pilot case list and assign operators.
2. Run tool on each case and collect output bundles.
3. Validate checksums and bundle integrity for each case.
4. Review redaction-report and manually inspect sample artifacts.
5. Aggregate manifest/redaction metrics using:

```powershell
.\scripts\Measure-PilotResults.ps1 -OutputRoot .\out -ReportPath .\pilot\pilot-metrics-report.json
```

6. Record findings in `pilot/PILOT_RESULTS.md`.
7. Tune defaults (include/exclude, event log lookback, redaction level) if needed.
8. Prepare release sign-off package.
