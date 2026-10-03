#!/usr/bin/env bash
# Test runner. Plain bash, no root, no system reads: diff and report run on the
# synthetic snapshots in tests/fixtures/study.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

S=tests/fixtures/study
pass=0 fail=0

ok() { pass=$((pass + 1)); echo "ok   $1"; }
not_ok() { fail=$((fail + 1)); echo "FAIL $1"; }

# expect_output <name> <expected-file> <command...>
expect_output() {
  local name=$1 expected=$2
  shift 2
  if diff -u "$expected" <("$@" 2>&1); then ok "$name"; else not_ok "$name"; fi
}

# expect_status <name> <status> <stderr-substring> <command...>
expect_status() {
  local name=$1 want=$2 needle=$3 err got
  shift 3
  err=$("$@" 2>&1 >/dev/null)
  got=$?
  if [[ $got == "$want" && $err == *"$needle"* ]]; then ok "$name"; else not_ok "$name (status $got: $err)"; fi
}

expect_output "diff before/after matches golden output" tests/expected/diff.txt ./footprint.sh diff "$S/00-before" "$S/01-after"
expect_output "report matches golden output" tests/expected/report.md ./footprint.sh report "$S"

if ./footprint.sh diff "$S/01-after" "$S/02-later" | grep -v '^== .* (+0 -0)$' | grep -q .; then
  not_ok "PID and ephemeral port changes are not reported"
else
  ok "PID and ephemeral port changes are not reported"
fi

if ./footprint.sh --help | grep -q 'sudo'; then ok "--help explains sudo"; else not_ok "--help explains sudo"; fi
expect_status "snapshot refuses an existing directory" 1 "already exists" ./footprint.sh snapshot 00-before "$S"
expect_status "snapshot rejects an unsafe label" 1 "label" ./footprint.sh snapshot ../x "$S"
expect_status "diff rejects a non-snapshot directory" 1 "not a snapshot" ./footprint.sh diff tests "$S/01-after"
expect_status "report needs two snapshots" 1 "fewer than two" ./footprint.sh report "$S/00-before"
expect_status "unknown command prints usage" 2 "Usage" ./footprint.sh frobnicate

echo "$pass passed, $fail failed"
((fail == 0))
