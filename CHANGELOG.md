# Changelog

## 0.1.0 (2026-10-05)

### Added

- `footprint.sh`: `snapshot`, `diff` and `report` for before/after studies of macOS installers. Eight snapshot files plus `meta.txt` (macOS version and build) and `fs-errors.txt` (folders that `find` cannot read). `snapshot` stops on a malformed `FOOTPRINT_FS_ROOTS` entry and on a system other than macOS.
- `tools/redact.py` and `tools/verify_redaction.sh`: redaction of raw captures and a gate that fails on personal data in tracked files, and with `--history` in every commit's files and message. Claude Code's co-author address and GitHub noreply addresses are allowed.
- `tools/check_citations.py`: checks that every citation in the evidence files opens at the cited raw line.
- `tools/check_sentences.py`: fails on a sentence of more than 25 words outside tables in the two README files.
- `tests/run.sh`: fixture-based tests for `diff` and `report`, planted-data tests for the verifier and the citation check.
- CI: ShellCheck, tests, the redaction gate and the sentence check on every push. The redaction gate also scans the full history.
- Case study: Omnissa Horizon Client installer. Findings tables, limits and reproduction steps, with line-cited evidence in `case-studies/omnissa-horizon-client/evidence/`.

### Notes

- Commit policy: from 5 October 2026, commits carry Claude Code's default `Co-Authored-By` trailer. Earlier commits have none. The redaction gate allows the address of this trailer.
