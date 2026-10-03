#!/usr/bin/env bash
# verify_redaction.sh - fail if any tracked file holds personal data.
# Scans tracked files (git grep) for: the real username and hostname and the
# REDACT_DENY strings from tools/.redact-local.env, any *-MacBook-* hostname,
# /Users/<name> paths, LAN and carrier-grade NAT IPv4 addresses, public IPv4 addresses that are not
# in ALLOW_IPS, MAC addresses, serial-like tokens, email addresses, and raw
# capture files. Exit 0 = clean, 1 = hits (printed), 2 = setup error.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Public IPs the case study may cite: remote endpoints of vendor processes.
ALLOW_IPS="23.40.244.164"

env_file=tools/.redact-local.env
user='' host='' deny=''
if [[ -f $env_file ]]; then
  user=$(sed -n 's/^REDACT_USER=//p' "$env_file")
  host=$(sed -n 's/^REDACT_HOST=//p' "$env_file")
  deny=$(sed -n 's/^REDACT_DENY=//p' "$env_file")
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
gg() { git grep -n -I "$@" || true; }

if [[ -n $user ]]; then
  report username "$(gg -i -E -e "(^|[^A-Za-z0-9])${user}([^A-Za-z0-9]|$)")"
  report hostname "$(gg -i -F -e "$host" -e "${host//-/ }")"
  IFS=',' read -r -a deny_list <<<"$deny"
  for d in "${deny_list[@]}"; do
    if [[ -n $d ]]; then report "deny:$d" "$(gg -i -F -e "$d")"; fi
  done
fi
report mac-hostname "$(gg -E -e '[A-Za-z0-9]+-MacBook-(Air|Pro)')"
report home-path "$(gg -E -e '/Users/[A-Za-z0-9_]')"
report lan-ip "$(gg -E -e '(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}')"
report mac-address "$(gg -E -e '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')"
report email "$(gg -E -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')"
# serial-like: 10-12 uppercase letters and digits, with at least one of each
report serial "$(gg -o -w -E -e '[A-Z0-9]{10,12}' | awk -F: '$NF ~ /[A-Z]/ && $NF ~ /[0-9]/')"
# public IPv4 not in ALLOW_IPS (private, loopback, multicast, test and reserved ranges pass)
report public-ip "$(gg -o -E -e '[0-9]{1,3}(\.[0-9]{1,3}){3}' | awk -F: -v allow=" $ALLOW_IPS " '{
  split($NF, o, ".")
  if (o[1] > 255 || o[2] > 255 || o[3] > 255 || o[4] > 255) next
  if (index(allow, " " $NF " ")) next
  if (o[1] == 0 || o[1] == 10 || o[1] == 127 || o[1] >= 224) next
  if (o[1] == 192 && o[2] == 168) next
  if (o[1] == 172 && o[2] >= 16 && o[2] <= 31) next
  if (o[1] == 100 && o[2] >= 64 && o[2] <= 127) next
  if (o[1] == 169 && o[2] == 254) next
  if (o[1] == 192 && o[2] == 0 && o[3] == 2) next
  if (o[1] == 198 && o[2] == 51 && o[3] == 100) next
  if (o[1] == 203 && o[2] == 0 && o[3] == 113) next
  print
}')"
report raw-file "$(git ls-files | grep -E '\.(pcap|pcapng|log)$|fs_usage|(^|/)\.redact-local\.env$' || true)"

if ((hits)); then
  echo "verify_redaction.sh: $hits hit(s), see HIT lines above" >&2
  exit 1
fi
echo "verify_redaction.sh: clean ($(git ls-files | wc -l | tr -d ' ') tracked files checked)"
