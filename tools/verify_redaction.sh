#!/usr/bin/env bash
# verify_redaction.sh - fail if the repository holds personal data.
#   verify_redaction.sh            scan the files staged in the git index
#   verify_redaction.sh --history  scan every commit as well
# Checks: the real username and hostname and the REDACT_DENY strings from
# tools/.redact-local.env, hostname-style MacBook model names, /Users/<name>
# paths, LAN, link-local and carrier-grade NAT IPv4, public IPv4 not in
# ALLOW_IPS, private and public IPv6, MAC addresses, UUIDs and UDIDs, per-user
# /var/folders IDs, serial-like tokens not in ALLOW_TOKENS, email addresses,
# raw capture files and files over 500 KB.
# Exit 0 = clean, 1 = hits (printed), 2 = setup error.
# Values split across string literals (as in test code) cannot be found by
# grep: test values must be synthetic, never copied from real captures.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Public IPs the case study may cite: remote endpoints of vendor processes.
ALLOW_IPS="23.40.244.164"
# Serial-like tokens that are public identifiers: the vendor's code-signing team ID.
ALLOW_TOKENS="S2ZMFGQM93"

targets=(--cached)
if [[ ${1:-} == --history ]]; then
  read -r -a targets <<<"$(git rev-list --all | tr '\n' ' ')"
  ((${#targets[@]})) || { echo "verify_redaction.sh: no commits" >&2; exit 2; }
fi
[[ -n $(git ls-files) ]] || { echo "verify_redaction.sh: no tracked files" >&2; exit 2; }

env_file=tools/.redact-local.env
envval() { # envval KEY: value from env_file without quotes, spaces or CR
  local v
  v=$(sed -n "s/^$1=//p" "$env_file" | tail -n 1 | tr -d '\r')
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  v=${v#[\"\']}
  printf '%s' "${v%[\"\']}"
}
user='' host='' deny=''
if [[ -f $env_file ]]; then
  user=$(envval REDACT_USER)
  host=$(envval REDACT_HOST)
  deny=$(envval REDACT_DENY)
  [[ -n $user && -n $host ]] || { echo "verify_redaction.sh: set REDACT_USER and REDACT_HOST in $env_file" >&2; exit 2; }
elif [[ -n ${CI:-} ]]; then
  echo "note: $env_file not present (CI), username, hostname and deny-list checks skipped"
else
  echo "verify_redaction.sh: $env_file is missing; copy tools/.redact-local.env.example and fill it in" >&2
  exit 2
fi

hits=0
report() { # report <check> <git grep output>
  [[ -n $2 ]] || return 0
  hits=$((hits + $(wc -l <<<"$2")))
  while IFS= read -r line; do echo "HIT [$1] $line"; done <<<"$2"
}
gg() { # git grep over the targets; status 1 = no match, more = error
  local rc=0
  git grep -n -a "$@" "${targets[@]}" -- . || rc=$?
  if ((rc > 1)); then
    echo "verify_redaction.sh: git grep failed ($rc)" >&2
    exit 2
  fi
}

if [[ -n $user ]]; then
  report username "$(gg -i -E -e "(^|[^A-Za-z0-9])${user}([^A-Za-z0-9]|$)")"
  report hostname "$(gg -i -F -e "$host" -e "${host//-/ }" -e "${host//-/}")"
  if [[ -n $deny ]]; then
    IFS=',' read -r -a deny_list <<<"$deny"
    for d in "${deny_list[@]}"; do
      d=${d#"${d%%[![:space:]]*}"}
      if [[ -n $d ]]; then report "deny:$d" "$(gg -i -F -e "$d")"; fi
    done
  fi
fi
report mac-hostname "$(gg -i -E -e '-MacBook-(Air|Pro)')"
report home-path "$(gg -E -e '/Users/[A-Za-z0-9_]' -e '%2FUsers%2F[A-Za-z0-9_]')"
report lan-ip "$(gg -E -e '(^|[^0-9])192\.168\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])169\.254\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}')"
report mac-address "$(gg -E -e '(^|[^0-9A-Fa-f:-])([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}([^0-9A-Fa-f:-]|$)' \
  -e '(^|[^0-9A-Fa-f:-])([0-9A-Fa-f]{1,2}-){5}[0-9A-Fa-f]{1,2}([^0-9A-Fa-f:-]|$)')"
report uuid "$(gg -E -e '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' -e '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}')"
report var-folders "$(gg -E -e '/folders/[A-Za-z0-9_+-]{2}/[A-Za-z0-9_+-]{20,}')"
report email "$(gg -E -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')"
# serial-like: 10-12 uppercase letters and digits, with at least one of each
report serial "$(gg -o -w -E -e '[A-Z0-9]{10,12}' | awk -F: -v allow=" $ALLOW_TOKENS " '$NF ~ /[A-Z]/ && $NF ~ /[0-9]/ && !index(allow, " " $NF " ")')"
# public IPv4 not in ALLOW_IPS (private, loopback, multicast, test and reserved ranges pass)
report public-ip "$(gg -o -E -e '[0-9]{1,3}(\.[0-9]{1,3}){3}' | awk -F: -v allow=" $ALLOW_IPS " '{
  split($NF, o, ".")
  if (o[1] > 255 || o[2] > 255 || o[3] > 255 || o[4] > 255) next
  if (index(allow, " " $NF " ")) next
  if (o[1] == 0 || o[1] == 10 || o[1] == 127 || o[1] >= 224) next
  if (o[1] == 192 && o[2] == 168) next
  if (o[1] == 172 && o[2] >= 16 && o[2] <= 31) next
  if (o[1] == 169 && o[2] == 254) next
  if (o[1] == 100 && o[2] >= 64 && o[2] <= 127) next
  if (o[1] == 192 && o[2] == 0 && o[3] == 2) next
  if (o[1] == 198 && o[2] == 51 && o[3] == 100) next
  if (o[1] == 203 && o[2] == 0 && o[3] == 113) next
  print
}')"
# IPv6: unique local (first group fc or fd), link-local (fe8 to feb) and global
# (2xxx, 3xxx). Loopback, multicast, documentation (2001:db8), times and
# MAC-like strings pass.
report ipv6 "$(gg -o -E -e '[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,7}' | awk '{
  a = $0
  if (a ~ /^[0-9a-f]{40}:/) sub(/^[^:]*:/, "", a)   # history mode: drop "rev:"
  sub(/^[^:]*:[0-9]+:/, "", a)                      # drop "file:line:"
  n = split(a, g, ":"); mac = 1
  for (i = 1; i <= n; i++) if (length(g[i]) != 2) mac = 0
  if (mac) next
  if (a !~ /::/ && n < 5) next
  f = tolower(g[1])
  if (a ~ /^::/ || f ~ /^ff/) next
  if (tolower(a) ~ /^2001:0?db8:/) next
  if (f ~ /^f[cd]/ || f ~ /^fe[89ab]/ || (length(f) == 4 && f ~ /^[23]/)) print
}')"
report raw-file "$(git ls-files | grep -E '\.(pcap|pcapng|log)$|(^|/)\.redact-local\.env$' || true)"
# raw captures are large; excerpts are not
report large-file "$(git ls-files -z | xargs -0 wc -c | awk '$2 != "total" && $1 > 512000 {print $2 ": " $1 " bytes"}')"

scope="$(git ls-files | wc -l | tr -d ' ') tracked files"
[[ ${targets[0]} == --cached ]] || scope="$scope, ${#targets[@]} commits"
if ((hits)); then
  echo "verify_redaction.sh: $hits hit(s) in $scope, see HIT lines above" >&2
  exit 1
fi
echo "verify_redaction.sh: clean ($scope checked)"
