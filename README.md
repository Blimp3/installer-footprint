# installer-footprint

[![CI](https://github.com/Blimp3/installer-footprint/actions/workflows/ci.yml/badge.svg)](https://github.com/Blimp3/installer-footprint/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`footprint.sh` takes a snapshot of a macOS system before and after an installer runs, and prints what the installer added.

**Why:** a macOS installer package can add more than the app. Its scripts can add background services, root helpers and further packages. Two snapshots and one diff show these changes: receipts, launchd jobs, helpers, files, processes and sockets.

**Case study:** on a test Mac, the Omnissa Horizon Client 8.17.0 installer also installed a Workspace ONE stack, Deem and the Endpoint Telemetry Service, with two daemons running as root ([case study](case-studies/omnissa-horizon-client/README.md), every claim tied to a cited fact):

| Added by the installer | Items | Facts |
| --- | --- | --- |
| Packages | Horizon Client 8.17.0, Deem 25.09.00.701 and its installer helper, Endpoint Telemetry Service 25.9.0.5699 | SET-20, SET-21, R1-19 |
| LaunchDaemons | `com.ws1.deemd` and `com.ws1.ws1etlm` (running as root), `com.omnissa.horizon.CDSHelper` (also a privileged helper) | R1-24, R1-32, R1-37, R1-93 |
| LaunchAgents | `com.ws1.ws1etlmu`, `com.ws1.deem.MacUIEvents` | R1-28 |
| System files | a line in `/etc/hosts`, a native-messaging manifest written to the Chrome and Edge folders, three links in `/usr/local/bin` | R1-40, R1-61, R1-52 |

The captures show what was installed and started. They do not show whether the components collected or sent any data. Fact IDs refer to [FACTS.md](case-studies/omnissa-horizon-client/evidence/FACTS.md).

## Quick start

Try `diff` and `report` on the synthetic snapshots in the repository. This needs no `sudo` and reads nothing from the system:

```bash
git clone https://github.com/Blimp3/installer-footprint
cd installer-footprint
./footprint.sh diff tests/fixtures/study/00-before tests/fixtures/study/01-after
./footprint.sh report tests/fixtures/study
```

Then study a real installer:

```bash
./footprint.sh snapshot 00-before ~/footprint-study
sudo installer -pkg ~/Downloads/Example.pkg -target /
./footprint.sh snapshot 01-after-install ~/footprint-study
./footprint.sh diff ~/footprint-study/00-before ~/footprint-study/01-after-install
./footprint.sh report ~/footprint-study > report.md
```

The tool needs only bash and the tools that come with macOS 13 or later. It reads the system and writes only into the directory you give it. It makes no network connections and never deletes or overwrites a file.

## What a snapshot holds

| File | Source | Complete without sudo? |
| --- | --- | --- |
| `receipts.txt` | `pkgutil --pkgs` | yes |
| `launchd.txt` | `ls -la` of `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `~/Library/LaunchAgents` | yes |
| `privhelpers.txt` | `ls -la /Library/PrivilegedHelperTools` | yes |
| `launchctl.txt` | `launchctl list` | no: a user sees the GUI domain, root sees the system domain |
| `hosts.txt` | `/etc/hosts` | yes |
| `fs.txt` | `find` over `FOOTPRINT_FS_ROOTS` (path:maxdepth list) | no: some of `/private/etc` is root-only |
| `processes.txt` | `ps -axo pid,ppid,user,comm` | yes |
| `connections.txt` | `lsof -nP -i` | no: a user sees only their own sockets |
| `meta.txt` | UTC time, macOS version and build, architecture, effective user id | yes |

Run every snapshot of one study the same way: all with `sudo`, or all without. `diff` compares entries, not raw lines. It ignores PIDs, file descriptors, ephemeral local ports and the per-launch numbers in GUI `launchctl` labels, so a restarted process or app does not show as a change. Run `./footprint.sh --help` for details.

## Run a three-phase study

Phase 1 is the install. Phase 2 is a permission grant (for example Full Disk Access). Phase 3 is normal use. Use a test Mac or a fresh user account if you can, and quit other apps to reduce noise.

1. Find your network interface: `route get default | grep interface` (for example `en0`).
2. In four separate terminals, start the captures. Stop each one with Ctrl-C at the end.
   - `sudo tcpdump -i en0 -nn -w capture.pcap`
   - `sudo tcpdump -i en0 -nn -l port 53 | tee dns.log`
   - `sudo fs_usage -w -f filesys > fs_usage.log` (this file grows fast; stop it after phase 1)
   - `sudo sh -c 'while sleep 10; do date +%T; lsof -nP -i -a -c <name>; done' | tee sockets.log` (sockets of processes whose name starts with `<name>`, every 10 s)
3. `mkdir study`, then `sudo ./footprint.sh snapshot 00-before study`
4. `sudo installer -pkg /path/to/Installer.pkg -target / -verbose | tee installer.log`
5. `sudo ./footprint.sh snapshot 01-after-install study`
6. Grant the permission in System Settings, then `sudo ./footprint.sh snapshot 02-after-permission study`.
7. Use the app for a fixed time (for example 10 minutes), then `sudo ./footprint.sh snapshot 03-final study`.
8. Export the unified log for the study window with `log show`, not `log stream`, so no messages are dropped. Name the vendor and the package script processes in the predicate:
   `log show --start "YYYY-MM-DD HH:MM:SS" --predicate 'process IN {"installer", "installd", "package_script_service"} OR senderImagePath CONTAINS[c] "vendor"' > unified.log`
9. Copy the package scripts' output: `sudo cp /var/log/install.log study/`
10. `./footprint.sh report study > study/REPORT.md`

Each snapshot records the macOS version in `meta.txt`. Write down the installer file name and its SHA-256 (`shasum -a 256`) before you start.

## How the redaction works

Raw captures hold your username, hostname, LAN addresses and a list of all the software you run. Nothing raw goes into this repository.

- `tools/redact.py` (Python 3, standard library only) produces every excerpt under `case-studies/*/evidence/`. It keeps only the lines its mode allows (vendor processes, vendor sockets, vendor DNS names, structural lines) and replaces each run of dropped lines with `[N unrelated lines removed]`. It replaces the username with `<user>`, the hostname with `<host>`, private IPs with `<lan-ip>` and other public IPs with `<ip>`. It removes MAC addresses, UUIDs, UDIDs, serial-like tokens and email addresses. With `--mask-unrelated` it replaces the names of other software in paths and bundle IDs with `<unrelated>`. It shortens runs of spaces, so column padding does not show the length of a masked name.
- The real username and hostname live in `tools/.redact-local.env`, which git ignores. Copy `tools/.redact-local.env.example` to create it. `REDACT_DENY` in that file lists more strings that must never appear, such as the names of your other software.
- `tools/verify_redaction.sh` scans the files in the git index and fails on any hit. It checks the values from `tools/.redact-local.env` and these patterns: hostname-style MacBook names, home paths, LAN, link-local and public IPv4 and IPv6 addresses, MAC addresses, UUIDs, UDIDs, per-user temporary folder IDs, serial-like tokens, email addresses, raw capture files and files over 500 KB. `--history` scans every commit as well. CI runs it on every push without the local file, so CI skips the username, hostname and deny-list checks.
- `tests/run.sh` plants each of these kinds of data in a scratch repository and checks that the verifier catches it. All test values are synthetic. A value split across string literals cannot be found by any grep, so test code must never copy values from real captures.

## Responsible use

- Observe software you are entitled to run, on machines you own or administer.
- Publish observations: file names, labels, versions, log messages and counts. Do not publish vendor binaries, packages or plist files verbatim.
- Report what the data shows. Mark what it cannot show.

## Tests

```bash
shellcheck footprint.sh tools/*.sh tests/*.sh
tests/run.sh
tools/verify_redaction.sh
```

`tests/run.sh` is plain bash. It tests `diff` and `report` on the synthetic snapshots in `tests/fixtures/`, so it needs no root and reads nothing from the system.

## License

MIT. See [LICENSE](LICENSE).
