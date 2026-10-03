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

if python3 tools/redact.py --self-test >/dev/null; then ok "redact.py self-test"; else not_ok "redact.py self-test"; fi

# verify_redaction.sh must catch planted personal data. Values are built at
# runtime so this file itself stays clean.
tmp=$(mktemp -d)
git -C "$tmp" init -q
mkdir "$tmp/tools"
cp tools/verify_redaction.sh "$tmp/tools/"
printf 'REDACT_USER=alex\nREDACT_HOST=%s\nREDACT_DENY=SecretCo\n' "Alexs-""MacBook-Air" >"$tmp/tools/.redact-local.env"
echo "clean line" >"$tmp/a.txt"
git -C "$tmp" add a.txt tools/verify_redaction.sh
expect_status "verifier passes a clean repo" 0 "" "$tmp/tools/verify_redaction.sh"
for planted in "TCP 192.""168.77.23:12345" "/Users/""alex/Library" "user alex here" "Alexs-""MacBook-Air.local" \
  "en0 a4:83:""e7:00:11:22" "mail someone""@example.org" "serial C02XK1""ZJG5H" "to 11.22.""33.44:443" "uses SecretCo"; do
  echo "$planted" >"$tmp/b.txt"
  git -C "$tmp" add b.txt
  expect_status "verifier catches: $planted" 1 "hit(s)" "$tmp/tools/verify_redaction.sh"
done
rm -rf "$tmp"

echo "$pass passed, $fail failed"
((fail == 0))
