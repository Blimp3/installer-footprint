#!/usr/bin/env bash
# Rebuild every excerpt in this folder from the raw analysis output. One line
# per excerpt, so each file's source and filter are on record. Needs the raw
# folders (under RAW_ROOT, default $HOME) and tools/.redact-local.env.
# Dropped lines and IP replacements go to .local/dropped.txt (git-ignored).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
raw=$(sed -n 's/^RAW_ROOT=//p' "$repo/tools/.redact-local.env" 2>/dev/null || true)
raw=${raw:-$HOME}
run1=$raw/pkg-analysis-20260625-120612
run2=$raw/manual-analysis-20260625-171808
dnscap=$raw/dns-capture/dns-20260625-171714.log
for p in "$run1" "$run2" "$dnscap"; do
  [[ -r $p ]] || { echo "build.sh: cannot read $p" >&2; exit 1; }
done
vendor_ip=23.40.244.164 # remote end of the horizon-client connections
mkdir -p "$repo/.local"
dropped=$repo/.local/dropped.txt
: >"$dropped"

team_id=S2ZMFGQM93     # vendor code-signing team ID (public)
redact() { python3 "$repo/tools/redact.py" --mask-unrelated --dropped "$dropped" --keep-ip "$vendor_ip" --keep-token "$team_id" "$@"; }

# snap <excerpt-name> <snapshot-dir> <label>: vendor lines of all eight files
snap() {
  local name=$1 dir=$2 label=$3
  {
    redact --mode list --label "$label/receipts.txt" "$dir/receipts.txt"
    redact --mode list --label "$label/launchd.txt" "$dir/launchd.txt"
    redact --mode list --label "$label/privhelpers.txt" "$dir/privhelpers.txt"
    redact --mode list --label "$label/launchctl.txt" "$dir/launchctl.txt"
    redact --mode text --label "$label/hosts.txt" "$dir/hosts.txt"
    redact --mode list --label "$label/fs.txt" "$dir/fs.txt"
    redact --mode proc --label "$label/processes.txt" "$dir/processes.txt"
    redact --mode net --label "$label/connections.txt" "$dir/connections.txt"
  } >"$here/$name.txt"
}

# fpdiff <excerpt-name> <before> <after> <label>: footprint.sh diff, vendor lines only
fpdiff() {
  "$repo/footprint.sh" diff "$2" "$3" | redact --mode list --no-number --label "$4" - >"$here/$1.txt"
}

# Snapshots
snap run1-install.snapshot-before "$run1/snapshot-before" run1/snapshot-before
snap run1-install.snapshot-after "$run1/snapshot-after" run1/snapshot-after
snap run2-p1-install.snap-00-before "$run2/snap-00-before" run2/snap-00-before
snap run2-p1-install.snap-01-after-install "$run2/snap-01-after-install" run2/snap-01-after-install
snap run2-p2-fda.snap-02-after-fda "$run2/snap-02-after-fda" run2/snap-02-after-fda
snap run2-p3-observe.snap-03-final "$run2/snap-03-final" run2/snap-03-final

# footprint.sh diff per phase, run on the raw snapshots
fpdiff run1-install.footprint-diff "$run1/snapshot-before" "$run1/snapshot-after" "footprint.sh diff run1/snapshot-before run1/snapshot-after"
fpdiff between-runs.footprint-diff "$run1/snapshot-after" "$run2/snap-00-before" "footprint.sh diff run1/snapshot-after run2/snap-00-before"
fpdiff run2-p1-install.footprint-diff "$run2/snap-00-before" "$run2/snap-01-after-install" "footprint.sh diff run2/snap-00-before run2/snap-01-after-install"
fpdiff run2-p2-fda.footprint-diff "$run2/snap-01-after-install" "$run2/snap-02-after-fda" "footprint.sh diff run2/snap-01-after-install run2/snap-02-after-fda"
fpdiff run2-p3-observe.footprint-diff "$run2/snap-02-after-fda" "$run2/snap-03-final" "footprint.sh diff run2/snap-02-after-fda run2/snap-03-final"

# Reports written by the original analysis scripts
redact --mode list --label run1/DIFF-report.txt "$run1/DIFF-report.txt" >"$here/run1-install.DIFF-report.txt"
redact --mode list --label run2/PHASE-DIFFS.txt "$run2/PHASE-DIFFS.txt" >"$here/run2.PHASE-DIFFS.txt"
redact --mode list --label run1/NETWORK-summary.txt "$run1/NETWORK-summary.txt" >"$here/run1-install.NETWORK-summary.txt"

# DNS logs: vendor names only
redact --mode dns --label run1/dns.log "$run1/dns.log" >"$here/run1-install.dns.txt"
redact --mode dns --label run2/dns.log "$run2/dns.log" >"$here/run2.dns.txt"
redact --mode dns --label dns-capture/dns-20260625-171714.log "$dnscap" >"$here/run2.dns-capture.txt"

# Vendor sockets over time (lsof every 10 s)
redact --mode net --label run2/agent-connections.log "$run2/agent-connections.log" >"$here/run2.agent-connections.txt"

# Installer
redact --mode text --label run1/installer.log "$run1/installer.log" >"$here/run1-install.installer-log.txt"

# Lines that FACTS.md cites, from the large logs. Line numbers stay the raw ones.
# BEGIN cited lines (generated from FACTS.md)
cited_run1_unified=1-3,5,1051,1063,1243,1245,1247,1297,2001-2002,2038,2061,2073,2159-2168,2826,2843,2861,2863,2972,3620,3697,3700,4102,4121-4139,4152,4158-4160,4289,4317-4326,4354,4378-4387,4416-4425,4475,4608,4714,4718,5260-5299,5451,5505-5506,5513-5514,5521-5522,5529-5530,5733,5743,5755,5792,5825,5915,5919,5977,6167-6178,6180,6199,6433,6640,7397,7440,8862,9254,9262-9264,9674,9676-9677,9880-9881,9883
cited_run2_unified=1-3,77,3846,4121-4123,4202-4205,4308,4357,4393,4474,4479-4480,18284,18299,18323-18324,18327-18328,18462,18990,18996,19645,19857,19859,19909,20626-20627,20662,21054,21095,21180,21760,21768,21776-21778,22314,22362,22382,22425,22427,22723,22767,22780,22924,22947,22988,23035-23036,23084,23117,23159-23160,23202,24006,24027,24072-24073,24122-24123,24125-24127,24129-24130,24163,24177,24279,24286,24302,24338,24419,24499,24647,24688-24690,24708,24710,24715,24727,24730,24764-24766,24805-24806,24825,24827,24857,24877,24906,24910,26388,26433,26513,26991,27005-27006,27249,27251,27489,27524,27536,27550-27551,27610,27644,27975,27989,28067-28069,28138-28140,28145,28334,28379-28397,28400,28411,28413,28746,29623,29625,33030-33033,33108-33111,33254-33273,33276,33284,33287,33293,34599-34600,34881,34893,34896,34935,34941,34943,35099,35255,35615,35704-35705,35768,35770,35853,35867,36098,36357,38995,39325,39368,42142,42442,42600,42828,43302,43321-43322,43326-43328,43330-43332,43334-43337,43403,43405,44571,44617,44632,44654,44656,44671,44677,44688,44701,44799,44801,45572-45573,45636,45651,45714-45722,45724,45734,45756,45818-45819,45821,45872,46692,46712,46763,46783,46787,46847,46856,47431,47657,47669,47674-47675,48100,48359,48414,48447,48460-48461,48526,48650,48674,48688,48785,48975,49810-49868,50019,50044,50058-50059,50104-50106,50132,50165,50303-50305,50317,50337,50364-50366,50392,50396,50410,50412,50414,50426,50481,50488,50490-50491,50519,50533,50535,50537,50548,50550-50552,50575-50577,50602,50650,50740,50797,50996,51685,51687,51690,51693-51712
cited_run1_fs_usage=1,19,25,44,50,524,536,573,47835,47847,73790,89989,89991-89995,90003-90005,90009,90017,90019,90036,90057,90065,90133,90320,90324,90344,91653,110433-110437,110443-110445,110447,110459-110460,115819,127292,137841,138503,138551,154047,154095,170371-170373,170375-170379,170381-170384,170923,170962-170963,171025-171028,171031-171035,171049,171699,171704,171912,176738,176852,184180,187324-187327,190060-190203,190207,190211,190260,190300,190315,190379,190382-190383,190425,190449,190569,190623-190626,190631,190651-190655,190682-190684,190760,190777-190778,190794,190824,191015,191020,191784,203980,204221,204247,211132,217249,217792,217906,217912,218119,218786,218938,218941,219111,219123,219126-219127,219142-219143,219152,219176,219592-219594,219626-219627,220305,221252,221259-221260,221272-221273,221283,221286,221419,222193,222228,222390,222432,224070,224094,224116,224570,224576,224582,224864,228832,228834,229762,229764,229770,229772,229981,229985,230288,232614,273341,273357,273433,277492,277813,278019,278021,278042-278043
cited_run1_dump=1688,1698,1801,1804-1805,1808,1866,2109,2119,2125,2149,2158,2168,2174,2180-2184,2775,2787,2850,2928,3042,3126,3132,3138,3144,3150,3156,3162,3168,3174,3177,3186,3189,3204,3222,3264,3272,3290,3302,3338,3344,3350,3356,3394,3400,3406,3424,3430,3460,3466,3484,3490,3532,3538,3544,3550,3556,3580,3586,3589,3817,3820,3827,3830,3833,3839,3842,3845,3848,3851,3854,3857,3863,3887,3893,3899,3905,4277,4287,4417,4423,4429,4477,4623,4707,4713,4719,4725,4731,4737,4743,4749,4761,4767,4779,4791,4887,4929,4983,4989,4999,5005,5033,5057,5063,5066,5069,5075,5099,5105,5111,5130,5523,5533,5659,5665,5671,5719,5763,5773,5779,5911,6104,6122-6123,6167,6238,6297,6307,6313,6319,6325,6357,6399,6409,6415,6421,6427,6433,6439,6445,6451,6457-6553,6559,6565,6571,6577,6595,6601,6607,6962,7016,7022,7028,7056,7267,7285-7286,7304,7448,7488,7494,7500,7506,7512,7530,7536,7542,7548,7554,7588,7598,7604,7610,7616,7628,7634,7640,7646,7652,7658,7664,7682,7988,8042,8048,8054,8060,8066,8072,8078,8088,8094,8100,8106,8112,8122,8128,8224,8240,8246,8249,8252,8336,8426,8432,9216,9362,9368
cited_run2_agentnet_syslog=138-179
# END cited lines
redact --mode text --lines "$cited_run1_unified" --label run1/unified.log "$run1/unified.log" >"$here/run1-install.unified-log.txt"
redact --mode text --lines "$cited_run2_unified" --label run2/unified.log "$run2/unified.log" >"$here/run2.unified-log.txt"
redact --mode text --lines "$cited_run1_fs_usage" --label run1/fs_usage.filtered.log "$run1/fs_usage.filtered.log" >"$here/run1-install.fs_usage.txt"
# Packet capture: the loopback syslog flow, as "tcpdump -nn -A" prints it (dump line numbers).
# The sed drops the binary IP/UDP header bytes in front of each syslog message.
tcpdump -nn -A -r "$run1/capture.pcap" 2>/dev/null | sed -E 's/^.*(<1[0-9][0-9]>)/\1/' |
  redact --mode text --lines "$cited_run1_dump" --label "tcpdump -nn -A -r run1/capture.pcap (dump lines)" - >"$here/run1-install.pcap-syslog.txt"
{
  redact --mode dns --lines 1-7 --label "run2/AGENT-NETWORK.txt (DNS section)" "$run2/AGENT-NETWORK.txt"
  redact --mode net --lines 8-136 --label "run2/AGENT-NETWORK.txt (client sockets)" "$run2/AGENT-NETWORK.txt"
  redact --mode text --lines "$cited_run2_agentnet_syslog" --label "run2/AGENT-NETWORK.txt (installer log section)" "$run2/AGENT-NETWORK.txt"
} >"$here/run2.AGENT-NETWORK.txt"

# Aggregates over the fs_usage trace (69 MB) and the packet capture: counts and short lists only.
fs=$run1/fs_usage.filtered.log
vendor_re=' (deemd|ws1etlm|ws1etlmu)\.[0-9]+$'
writes_re='^[^ ]+ +(mkdir|mkfifo|unlink|unlinkat|rename|renameat|rmdir|chmod|chmodat|fchmodat|chown|symlink|link|truncate|(open|openat) +F=[0-9]+ +\(.W)'
proc_syscall() { awk '{p=$NF; sub(/\.[0-9]+$/, "", p); print p, $2}' | sort | uniq -c | sort -rn; }
{
  echo "## Size and time span"
  wc -l <"$fs"
  sed -n '1p;$p' "$fs" | awk '{print $1}'
  echo "## Lines per process name: vendor and installer processes"
  awk '{p=$NF; sub(/\.[0-9]+$/, "", p); c[p]++} END {for (k in c) print c[k], k}' "$fs" |
    grep -E ' (deemd|ws1etlm|ws1etlmu|installer|installd|package_script_s|package_script_service)$' | sort -rn
  echo "## Write-type syscalls with a path by deemd, ws1etlm and ws1etlmu (all of them)"
  { grep -E "$vendor_re" "$fs" | grep -E "$writes_re" || true; }
  echo "## Lines that name /private/etc/master.passwd, by process and syscall"
  { grep 'etc/master.passwd' "$fs" || true; } | proc_syscall
  echo "## Vendor lines that name /private/var/log/asl, by process and syscall"
  { grep -E "$vendor_re" "$fs" | grep 'var/log/asl' || true; } | proc_syscall
  echo "## Vendor lines that name a path under /Users, by process and syscall"
  { grep -E "$vendor_re" "$fs" | grep '/Users/' || true; } | proc_syscall
  echo "## ws1etlm opens of */Contents/Info.plist: all, with a file descriptor, under /Applications"
  grep -E ' ws1etlm\.[0-9]+$' "$fs" | grep -E '^[^ ]+ +open ' | grep -c '/Contents/Info\.plist ' || true
  grep -E ' ws1etlm\.[0-9]+$' "$fs" | grep -E '^[^ ]+ +open +F=' | grep -c '/Contents/Info\.plist ' || true
  grep -E ' ws1etlm\.[0-9]+$' "$fs" | grep -E '^[^ ]+ +open +F=' | grep '/Contents/Info\.plist ' | grep -c ' /Applications/' || true
  echo "## Lines that name the AirWatch hub socket, by process and syscall"
  { grep 'hubudssocket' "$fs" || true; } | proc_syscall
} | redact --mode text --no-number --label "aggregates over run1/fs_usage.filtered.log (commands in build.sh)" - >"$here/run1-install.fs_usage-counts.txt"

pcap=$run1/capture.pcap
{
  echo "## Packets, first and last time"
  tcpdump -nn -r "$pcap" 2>/dev/null | wc -l
  tcpdump -nn -r "$pcap" 2>/dev/null | sed -n '1p;$p' | awk '{print $1}'
  echo "## Loopback syslog flow 127.0.0.1:52385 -> 127.0.0.1:32376: packets, and ICMP port-unreachable replies"
  tcpdump -nn -r "$pcap" 'udp and dst port 32376' 2>/dev/null | wc -l
  tcpdump -nn -r "$pcap" 'icmp and host 127.0.0.1' 2>/dev/null | grep -c 'udp port 32376 unreachable' || true
  echo "## Dump lines with a vendor string, by packet flow"
  tcpdump -nn -A -r "$pcap" 2>/dev/null |
    awk '/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+ /{hdr=$0; next} tolower($0) ~ /omnissa|vmware|workspaceone|airwatch|ws1|horizon|deem/ {split(hdr, h, " "); print h[3], h[4], h[5]}' |
    sort | uniq -c
  echo "## Distinct remote addresses on TCP 443 and on UDP 443 (addresses not listed)"
  tcpdump -nn -r "$pcap" 'tcp port 443' 2>/dev/null | awk '{print ($3 ~ /\.443$/ ? $3 : $5)}' | sed -E 's/\.[0-9]+:?$//' | sort -u | wc -l
  tcpdump -nn -r "$pcap" 'udp port 443' 2>/dev/null | awk '{print ($3 ~ /\.443$/ ? $3 : $5)}' | sed -E 's/\.[0-9]+:?$//' | sort -u | wc -l
  echo "## DNS: UDP 53, TCP 53 and port 853 packets"
  tcpdump -nn -r "$pcap" 'udp port 53' 2>/dev/null | wc -l
  tcpdump -nn -r "$pcap" 'tcp port 53' 2>/dev/null | wc -l
  tcpdump -nn -r "$pcap" 'port 853' 2>/dev/null | wc -l
  echo "## Packets to or from $vendor_ip"
  tcpdump -nn -r "$pcap" "host $vendor_ip" 2>/dev/null | wc -l
} | redact --mode text --no-number --label "aggregates over run1/capture.pcap (commands in build.sh)" - >"$here/run1-install.pcap-counts.txt"
