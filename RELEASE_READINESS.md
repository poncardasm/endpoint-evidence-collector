# Release Readiness Checklist (v1.0)

## Pilot and Validation

- [ ] Pilot executed with representative technicians and endpoints.
- [ ] Pilot metrics report generated (`pilot/pilot-metrics-report.json`).
- [ ] Median runtime target met (< 5 minutes).
- [ ] No confirmed unredacted credential/token leakage.
- [ ] Defaults tuned based on pilot findings.

## Security and Compliance

- [ ] `docs/PRD.md` Section 16 checklist reviewed and completed locally.
- [ ] Artifact integrity verified via `bundle.sha256` checks.
- [ ] Signature/encryption controls validated if used by policy.
- [ ] Approved transfer-channel guidance confirmed with support teams.

## Quality Gates

- [ ] CI passed on target release commit.
- [ ] Pester tests passed.
- [ ] Script analysis passed (PSScriptAnalyzer).
- [ ] Secret scanning passed.

## Release Outputs

- [ ] `CHANGELOG.md` updated for v1.0.
- [ ] Release notes prepared.
- [ ] Version tag created (`v1.0.0`).
- [ ] Release artifact/sample bundle attached as needed.

## Sign-off

- [ ] Product owner sign-off
- [ ] Security sign-off
- [ ] Support operations sign-off
