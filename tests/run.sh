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

out=$(./footprint.sh diff "$S/01-after" "$S/02-later") && rc=0 || rc=$?
if [[ $rc == 0 && $(grep -c '^== .* (+0 -0)$' <<<"$out") == 8 && $(grep -c "" <<<"$out") == 8 ]]; then
  ok "PID, fd, label and local port changes are not reported"
else
  not_ok "PID, fd, label and local port changes are not reported (status $rc)"
fi

moved=$(mktemp -d)
cp -R "$S/02-later" "$moved/03-moved"
sed -i.bak 's/127.0.0.1:55615 (LISTEN)/127.0.0.1:61234 (LISTEN)/' "$moved/03-moved/connections.txt"
out=$(./footprint.sh diff "$S/02-later" "$moved/03-moved")
if grep -q '^== connections.txt (+1 -1)$' <<<"$out"; then
  ok "a listener on a new port is reported"
else
  not_ok "a listener on a new port is reported"
fi
rm -rf "$moved"

if ./footprint.sh --help | grep -q 'sudo'; then ok "--help explains sudo"; else not_ok "--help explains sudo"; fi
expect_status "snapshot refuses an existing directory" 1 "already exists" ./footprint.sh snapshot 00-before "$S"
expect_status "snapshot rejects an unsafe label" 1 "label" ./footprint.sh snapshot ../x "$S"
expect_status "diff rejects a non-snapshot directory" 1 "not a snapshot" ./footprint.sh diff tests "$S/01-after"
expect_status "report needs two snapshots" 1 "fewer than two" ./footprint.sh report "$S/00-before"
expect_status "unknown command prints usage" 2 "Usage" ./footprint.sh frobnicate
bad=$(mktemp -d)
expect_status "snapshot rejects a malformed FOOTPRINT_FS_ROOTS entry" 1 "FOOTPRINT_FS_ROOTS" \
  env FOOTPRINT_FS_ROOTS='/Library/Application Support:4 /private/etc:3' ./footprint.sh snapshot x "$bad"
if [[ ! -e $bad/x ]]; then ok "a rejected snapshot writes nothing"; else not_ok "a rejected snapshot writes nothing"; fi
rm -rf "$bad"

if python3 tools/redact.py --self-test >/dev/null; then ok "redact.py self-test"; else not_ok "redact.py self-test"; fi

if python3 tools/check_citations.py >/dev/null; then ok "every FACTS citation resolves"; else not_ok "every FACTS citation resolves"; fi
cit=$(mktemp -d)
printf '# source: x.log | mode=text\n    10  first\n    12  second\n' >"$cit/x.txt"
# shellcheck disable=SC2016 # literal backticks of a Markdown citation
printf -- '- **T-1** Evidence: [`x.txt:12`](x.txt#L2).\n' >"$cit/FACTS.md"
expect_status "citation check catches a wrong anchor" 1 "do not resolve" python3 tools/check_citations.py "$cit/FACTS.md"
rm -rf "$cit"

# verify_redaction.sh must catch planted personal data. The values are
# synthetic and split so this file itself stays clean.
# The verifier runs under "timeout 60" where that command exists (Linux CI).
verify() { if command -v timeout >/dev/null; then timeout 60 "$@"; else "$@"; fi; }
tmp=$(mktemp -d)
id=(-c user.name=Blimp3 -c "user.email=91412057+Blimp3""@users.noreply.github.com")
git -C "$tmp" init -q
mkdir "$tmp/tools"
cp tools/verify_redaction.sh "$tmp/tools/"
printf 'REDACT_USER=alex\nREDACT_HOST=%s\nREDACT_DENY=\n' "Alexs-""MacBook-Air" >"$tmp/tools/.redact-local.env"
echo "clean line, window 17:18:10-17:29:38, ::1 and ff02::fb" >"$tmp/a.txt"
git -C "$tmp" add a.txt tools/verify_redaction.sh
expect_status "verifier passes a clean repo (empty deny list)" 0 "" verify "$tmp/tools/verify_redaction.sh"
printf 'REDACT_USER="alex"\nREDACT_HOST=%s\nREDACT_DENY=SecretCo, OtherCo\n' "Alexs-""MacBook-Air" >"$tmp/tools/.redact-local.env"
for planted in "TCP 192.""168.77.23:12345" "/Users/""alex/Library" "user alex here" "Alexs-""MacBook-Air.local" \
  "AlexsMacBook""Air" "host x-MacBook""-Pro" "en0 a4:83:""e7:00:11:22" "en1 a4-83-""e7-00-11-22" \
  "mail someone""@example.org" "serial C02XK1""ZJG5H" "to 11.22.""33.44:443" "uses OtherCo" \
  "[fd12:3456:""789a:1::5]:80" "via fe""80::1c2:3ff:fe4:5" "id 11111111-2222-""4333-8444-555555555555" \
  "/var/folders/qq/""abcdefghijklmnopqrstuvwx/T" "gw 10.""20.30.40" "nat 172.""20.1.2" "ll 169.""254.10.20" \
  "cgn 100.""64.1.2" "v6 2a01""::4" "udid 00008103-""001A2C3E0E43001E"; do
  echo "$planted" >"$tmp/b.txt"
  git -C "$tmp" add b.txt
  expect_status "verifier catches: $planted" 1 "hit(s)" verify "$tmp/tools/verify_redaction.sh"
done
echo "clean" >"$tmp/b.txt"
git -C "$tmp" add b.txt
for f in capture.pcap fs_usage.log tools/.redact-local.env; do
  [[ -e $tmp/$f ]] || : >"$tmp/$f"
  git -C "$tmp" add -f "$f"
  expect_status "verifier catches a tracked $f" 1 "hit(s)" verify "$tmp/tools/verify_redaction.sh"
  git -C "$tmp" rm -q --cached "$f"
done
head -c 600000 /dev/zero | tr '\0' 'x' >"$tmp/big.txt"
git -C "$tmp" add big.txt
expect_status "verifier catches a file over 500 KB" 1 "hit(s)" verify "$tmp/tools/verify_redaction.sh"
git -C "$tmp" rm -q --cached big.txt
echo "by 91412057+Blimp3""@users.noreply.github.com" >"$tmp/b.txt"
git -C "$tmp" add b.txt
git -C "$tmp" "${id[@]}" commit -q -m "Add notes" -m "Co-Authored-By: Claude <noreply""@anthropic.com>"
expect_status "verifier allows a Co-Authored-By trailer and a noreply address" 0 "" verify "$tmp/tools/verify_redaction.sh" --history
git -C "$tmp" "${id[@]}" commit -q --allow-empty -m "Add more notes" -m "seen at alex's desk"
expect_status "verifier --history catches a commit message" 1 "hit(s)" verify "$tmp/tools/verify_redaction.sh" --history
rm -rf "$tmp"

echo "$pass passed, $fail failed"
((fail == 0))
