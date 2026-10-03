# Changelog

## Unreleased

### Added

- `footprint.sh`: `snapshot`, `diff` and `report` for before/after studies of macOS installers. Eight snapshot files plus `meta.txt` (macOS version and build).
- `tools/redact.py` and `tools/verify_redaction.sh`: redaction of raw captures and a gate that fails on personal data in tracked files.
- `tests/run.sh`: fixture-based tests for `diff` and `report`, and planted-data tests for the verifier.
- CI: ShellCheck, tests and the redaction gate on every push.
- Case study: Omnissa Horizon Client installer, line-cited evidence in `case-studies/omnissa-horizon-client/evidence/`.

### GitHub setup (prepared, not applied)

- Description (114 characters): "Snapshot-and-diff tool for what a macOS installer adds, with a case study of the Omnissa Horizon Client installer."
- Topics: `macos`, `security-research`, `installer-analysis`, `launchd`, `endpoint-telemetry`, `privacy`, `workspace-one`, `omnissa-horizon`, `bash`
- Pin the repository on the profile next to `provenance-lens-extension`, `digibot` and `LocalTransciber`.
