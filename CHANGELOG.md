# Changelog

## Unreleased (0.1.0)

### Added

- `footprint.sh`: `snapshot`, `diff` and `report` for before/after studies of macOS installers. Eight snapshot files plus `meta.txt` (macOS version and build) and `fs-errors.txt` (folders that `find` could not read). `snapshot` stops on a malformed `FOOTPRINT_FS_ROOTS` entry.
- `tools/redact.py` and `tools/verify_redaction.sh`: redaction of raw captures and a gate that fails on personal data in tracked files, and with `--history` in every commit's files and message. Claude Code's co-author address and GitHub noreply addresses are allowed.
- `tools/check_citations.py`: checks that every citation in the evidence files opens at the cited raw line.
- `tests/run.sh`: fixture-based tests for `diff` and `report`, planted-data tests for the verifier and the citation check.
- CI: ShellCheck, tests and the redaction gate on every push.
- Case study: Omnissa Horizon Client installer. Findings tables, limits and reproduction steps, with line-cited evidence in `case-studies/omnissa-horizon-client/evidence/`.

