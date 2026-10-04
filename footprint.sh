#!/usr/bin/env bash
# footprint.sh - snapshot a macOS system before and after an installer runs,
# then show what changed. Reads the system only: no network access, and it
# never deletes or overwrites anything.
set -euo pipefail
export LC_ALL=C # stable sort and comm order

VERSION=0.1.0
FILES=(receipts launchd privhelpers launchctl hosts fs processes connections)

usage() {
  cat <<'EOF'
Usage:
  footprint.sh snapshot <label> [dir]   Write a snapshot to <dir>/<label>/ (dir defaults to .)
  footprint.sh diff <before> <after>    Print what was added (+) and removed (-) between two snapshots
  footprint.sh report <dir>             Diff each consecutive pair of snapshots in <dir> (sorted by
                                        name) and print a Markdown report
  footprint.sh --help | --version

A snapshot is one directory with eight files plus meta.txt:
  receipts.txt     pkgutil --pkgs
  launchd.txt      ls -la /Library/LaunchAgents /Library/LaunchDaemons ~/Library/LaunchAgents
  privhelpers.txt  ls -la /Library/PrivilegedHelperTools
  launchctl.txt    launchctl list
  hosts.txt        /etc/hosts
  fs.txt           find over FOOTPRINT_FS_ROOTS ("path:maxdepth;path:maxdepth"), default:
                   /Library/Application Support:4  /private/etc:3  /usr/local/bin:1
                   /Applications:1  ~/Library/Application Support:2
  processes.txt    ps -axo pid,ppid,user,comm
  connections.txt  lsof -nP -i
  meta.txt         UTC time, macOS version and build, architecture, effective user id

Runs as a normal user. Three parts are incomplete without sudo:
  - connections.txt: lsof lists only your own processes' sockets
  - launchctl.txt:   you see your GUI domain; root sees the system domain (LaunchDaemons)
  - fs.txt:          some directories under /private/etc are not readable
Run "sudo footprint.sh snapshot <label> <dir>" for the full picture. Take every
snapshot of one study the same way (all with sudo, or all without).

diff compares entries, not raw lines. It ignores PIDs, file descriptors, the local
end of connected sockets, the local port of unconnected sockets and the per-launch
numbers in GUI launchctl labels, so a restarted process or app is not reported as
a change. A listener that moves to a new port is reported. Each entry is listed
once, so a second copy of the same process does not show.
It compares names, so a file replaced under the same name does not show.

Snapshots contain your username, hostname, LAN addresses and the list of software
you run. Do not publish them unredacted.
EOF
}

die() { echo "footprint.sh: $*" >&2; exit 1; }

# The invoking user's home, also under sudo.
user_home() {
  local h=$HOME
  if [[ $EUID == 0 && -n ${SUDO_USER:-} ]]; then
    # dscl prints "NFSHomeDirectory: /path" or, for a path with spaces, the path on the next line
    h=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory)
    h=${h#NFSHomeDirectory:}
    h=${h#"${h%%[![:space:]]*}"}
  fi
  [[ -d $h ]] || die "cannot find the home folder of ${SUDO_USER:-$USER}"
  echo "$h"
}

fs_list() { # fs_list <home>
  local spec root depth
  local -a specs
  # path:maxdepth pairs, separated by ";"
  local roots="/Library/Application Support:4;/private/etc:3;/usr/local/bin:1;/Applications:1;$1/Library/Application Support:2"
  IFS=';' read -r -a specs <<<"${FOOTPRINT_FS_ROOTS:-$roots}"
  for spec in "${specs[@]}"; do
    root=${spec%:*} depth=${spec##*:}
    [[ -e $root ]] || continue
    find -H "$root" -maxdepth "$depth" 2>/dev/null || true
  done | sort
}

snapshot() {
  local label=${1:-} dir=${2:-.} out d home
  [[ $label =~ ^[A-Za-z0-9._-]+$ ]] || die "snapshot needs a label of letters, digits, . _ or -"
  out=$dir/$label
  [[ ! -e $out ]] || die "$out already exists; pick a new label (snapshots are never overwritten)"
  mkdir -p "$dir"
  mkdir "$out"
  echo "footprint.sh: writing $out" >&2
  home=$(user_home)

  pkgutil --pkgs | sort >"$out/receipts.txt"
  for d in /Library/LaunchAgents /Library/LaunchDaemons "$home/Library/LaunchAgents"; do
    echo "$d:"
    ls -la "$d" 2>&1 || true
    echo
  done >"$out/launchd.txt"
  ls -la /Library/PrivilegedHelperTools >"$out/privhelpers.txt" 2>&1 || true
  launchctl list | sort -k3 >"$out/launchctl.txt"
  cat /etc/hosts >"$out/hosts.txt"
  fs_list "$home" >"$out/fs.txt"
  ps -axo pid,ppid,user,comm | sort -n >"$out/processes.txt"
  { lsof -nP -i 2>/dev/null || true; } | sort >"$out/connections.txt"
  {
    echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "arch: $(uname -m)"
    echo "euid: $(id -u)"
    echo "footprint: $VERSION"
  } >"$out/meta.txt"
}

# keys <snapshot-dir> <file>: one comparable entry per line, sorted and unique.
keys() {
  local f=$1/$2
  [[ -f $f ]] || return 0
  case $2 in
    launchd.txt | privhelpers.txt)
      # ls -la output: an entry is "<dir>/<name>"; "<dir>:" lines set the dir
      awk '
        /^\/.*:$/ { dir = substr($0, 1, length($0) - 1); next }
        length($1) >= 10 && $1 ~ /^[-bcdlps][-rwxsStT]+[@+.]?$/ && NF >= 9 {
          n = $0
          for (k = 0; k < 8; k++) sub(/^[^ ]+ +/, "", n)
          if (n != "." && n != "..") print (dir == "" ? n : dir "/" n)
        }' "$f"
      ;;
    launchctl.txt)
      # GUI-domain labels end in per-launch numbers (application.<id>.<n>.<n>)
      awk 'NF >= 3 && $3 != "Label" { l = $3; if (l ~ /^application\./) sub(/(\.[0-9]+)+$/, "", l); print l }' "$f"
      ;;
    processes.txt)
      # drop PID and PPID, keep "user command"
      awk '$1 ~ /^[0-9]+$/ { sub(/^ *[0-9]+ +[0-9]+ +/, ""); sub(/ +/, " "); print }' "$f"
      ;;
    connections.txt)
      # lsof: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME [(STATE)]
      # keep command, user, protocol, remote end (or listening address)
      awk '$2 ~ /^[0-9]+$/ && NF >= 9 {
        name = $9; state = (NF >= 10 ? " " $10 : "")
        if (name ~ /->/) sub(/^.*->/, "->", name)
        else if (state != " (LISTEN)") sub(/:[0-9]+$/, ":*", name)
        print $1, $3, $8, name state
      }' "$f"
      ;;
    *) grep -v '^[[:space:]]*$' "$f" || true ;;
  esac | sort -u
}

# changes <before> <after> <file>: "+ entry" and "- entry" lines
changes() {
  local a b
  a=$(keys "$1" "$3")
  b=$(keys "$2" "$3")
  comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -v '^$' | sed 's/^/+ /' || true
  comm -23 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -v '^$' | sed 's/^/- /' || true
}

is_snapshot() {
  local f
  [[ -f $1/receipts.txt ]] || die "$1 is not a snapshot directory (no receipts.txt)"
  for f in "${FILES[@]}"; do
    if [[ -e $1/$f.txt && ! -r $1/$f.txt ]]; then die "$1/$f.txt is not readable (try sudo)"; fi
  done
}

diff_snap() {
  local f out
  is_snapshot "$1"
  is_snapshot "$2"
  for f in "${FILES[@]}"; do
    out=$(changes "$1" "$2" "$f.txt")
    printf '== %s.txt (+%d -%d)\n' "$f" "$(grep -c '^+ ' <<<"$out" || true)" "$(grep -c '^- ' <<<"$out" || true)"
    if [[ -n $out ]]; then printf '%s\n' "$out"; fi
  done
}

report() {
  local dir=${1:-} s i f out cell row
  local -a snaps=() same
  [[ -d $dir ]] || die "report needs a directory that holds snapshots"
  for s in "$dir"/*/; do
    if [[ -f $s/receipts.txt ]]; then snaps+=("${s%/}"); fi
  done
  ((${#snaps[@]} >= 2)) || die "$dir holds fewer than two snapshots"
  for s in "${snaps[@]}"; do is_snapshot "$s"; done

  echo "# Footprint report"
  echo
  echo "Snapshots: ${snaps[*]##*/}"
  echo
  printf '| Step |'; printf ' %s |' "${FILES[@]}"; echo
  printf '|---|'; printf -- '---|%.0s' "${FILES[@]}"; echo
  for ((i = 1; i < ${#snaps[@]}; i++)); do
    row="| ${snaps[i - 1]##*/} -> ${snaps[i]##*/} |"
    for f in "${FILES[@]}"; do
      out=$(changes "${snaps[i - 1]}" "${snaps[i]}" "$f.txt")
      if [[ -z $out ]]; then cell=" ."; else cell=" +$(grep -c '^+ ' <<<"$out" || true) -$(grep -c '^- ' <<<"$out" || true)"; fi
      row+="$cell |"
    done
    echo "$row"
  done
  echo
  echo '"." means no change.'
  for ((i = 1; i < ${#snaps[@]}; i++)); do
    echo
    echo "## ${snaps[i - 1]##*/} -> ${snaps[i]##*/}"
    same=()
    for f in "${FILES[@]}"; do
      out=$(changes "${snaps[i - 1]}" "${snaps[i]}" "$f.txt")
      if [[ -z $out ]]; then same+=("$f.txt"); continue; fi
      echo
      echo "### $f.txt"
      echo
      echo '```diff'
      printf '%s\n' "$out"
      echo '```'
    done
    if ((${#same[@]})); then
      echo
      echo "No change: ${same[*]}"
    fi
  done
}

case ${1:-} in
  snapshot) shift; snapshot "$@" ;;
  diff)
    (($# == 3)) || die "usage: footprint.sh diff <before> <after>"
    diff_snap "$2" "$3"
    ;;
  report) shift; report "$@" ;;
  -h | --help | help) usage ;;
  --version) echo "footprint.sh $VERSION" ;;
  *) usage >&2; exit 2 ;;
esac
