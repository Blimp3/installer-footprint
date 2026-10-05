# installer-footprint

[![CI](https://github.com/Blimp3/installer-footprint/actions/workflows/ci.yml/badge.svg)](https://github.com/Blimp3/installer-footprint/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`footprint.sh` takes a snapshot of a macOS system before and after an installer runs. It then prints what the installer adds.

**Why:** a macOS installer package can add more than the app. Its scripts can add background services, root helpers and more packages. Two snapshots and one diff show these changes: receipts, launchd jobs, helpers, files, processes and sockets.

**Case study:** the [case study](case-studies/omnissa-horizon-client/README.md) observes the installer for Omnissa Horizon Client 8.17.0 on a test Mac that also runs unrelated software. The installer installs three Workspace ONE packages by default, as the vendor documents. They are Deem, its installer helper and the Endpoint Telemetry Service. The case study records what this default adds: packages, LaunchDaemons, a root helper, entitlements and a line in `/etc/hosts`. The vendor documentation does not list these items. Every finding cites a fact from the captures or one of my marked notes.

This is the start of the `footprint.sh diff` output for run 1 of the case study:

```text
== receipts.txt (+4 -0)
+ com.omnissa.horizon.client.mac
+ com.ws1.Deem
+ com.ws1.Deem.InstallerHelper
+ com.ws1.EndpointTelemetryService
== launchd.txt (+5 -0)
+ /Library/LaunchAgents/com.ws1.deem.MacUIEvents.plist
+ /Library/LaunchAgents/com.ws1.ws1etlmu.plist
+ /Library/LaunchDaemons/com.omnissa.horizon.CDSHelper.plist
+ /Library/LaunchDaemons/com.ws1.deemd.plist
+ /Library/LaunchDaemons/com.ws1.ws1etlm.plist
== privhelpers.txt (+1 -0)
+ com.omnissa.horizon.CDSHelper
== launchctl.txt (+3 -0)
+ com.omnissa.horizon.CDSHelper
+ com.ws1.deemd
+ com.ws1.ws1etlm
== hosts.txt (+1 -0)
+ 127.0.0.1 view-localhost
== fs.txt (+33 -0)
...
```

The [full run 1 diff](case-studies/omnissa-horizon-client/evidence/run1-install.footprint-diff.txt) also lists the 33 new paths and the changes to processes and sockets. The captures show what the installer installs and starts. They do not show whether the components collect or send data. The captures come from earlier scripts, not from `footprint.sh`. `footprint.sh diff` runs over their snapshots afterwards.

## Quick start

In a clone of this repository, try `diff` and `report` on the synthetic snapshots. These commands need no `sudo` and read nothing from the system:

```bash
./footprint.sh diff tests/fixtures/study/00-before tests/fixtures/study/01-after
./footprint.sh report tests/fixtures/study
```

Then study a real installer. Use `sudo` for the snapshots, so that they include the system launchd domain and root sockets:

```bash
mkdir ~/footprint-study
sudo ./footprint.sh snapshot 00-before ~/footprint-study
sudo installer -pkg ~/Downloads/Example.pkg -target /
sudo ./footprint.sh snapshot 01-after-install ~/footprint-study
./footprint.sh diff ~/footprint-study/00-before ~/footprint-study/01-after-install
./footprint.sh report ~/footprint-study > report.md
```

`footprint.sh` needs only bash and the tools that come with macOS. I test it on macOS 27.0 with the system bash 3.2. It reads the system and writes only into the directory that you give it. It makes no network connections. It never deletes or overwrites a file.

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
| `fs-errors.txt` | folders that `find` cannot read or that do not exist. `diff` ignores this file | - |

The snapshots do not list system extensions, configuration profiles, kernel extensions or the database of Background Task Management.

Take every snapshot of one study the same way: all with `sudo` and the same `FOOTPRINT_FS_ROOTS`, or all without. Run `./footprint.sh --help` for details.

`diff` compares entries, not raw lines. It ignores PIDs, file descriptors and the per-launch numbers in GUI `launchctl` labels. It also ignores the local end of connected sockets and the local port of unconnected sockets. So a restarted process or app does not show as a change. A listener on a new port does show.

Each entry shows once, so a second copy of a process does not show. `diff` compares names, so it does not show a file that gets new content under the same name.

## Run a three-phase study

Phase 1 is the install. Phase 2 is a permission grant, for example Full Disk Access. Phase 3 is normal use. If you can, use a test Mac or a fresh user account. Quit other apps to reduce noise.

Five captures run in separate terminals. The `fs_usage` capture stops after phase 1. The other captures run for the whole study. Both log commands use one predicate. Replace `vendor` in it with a vendor term.

| File | Command | What it records |
| --- | --- | --- |
| `capture.pcap` | `sudo tcpdump -i en0 -nn -w capture.pcap` | all packets on the interface |
| `dns.log` | `sudo tcpdump -i en0 -nn -l port 53 \| tee dns.log` | DNS queries on port 53. Encrypted DNS on port 443 does not show here |
| `fs_usage.log` | `sudo fs_usage -w -f filesys > fs_usage.log` | file system calls. This file grows fast |
| `sockets.log` | `sudo sh -c 'while sleep 10; do date +%T; lsof -nP -i; done' \| tee sockets.log` | the sockets of all processes, every 10 s. Before the install, you do not know the names of the vendor processes |
| `stream.log` | `/usr/bin/log stream --level debug --predicate 'process IN {"installer", "installd", "package_script_service"} OR senderImagePath CONTAINS[c] "vendor"' > stream.log` | the live unified log |

`/usr/bin/log` avoids the `log` builtin of zsh. `log stream` can drop messages. `log show` drops none, but it returns Debug lines only if macOS stores them. So keep both logs.

`sudo` resets the environment, so each snapshot gets the folder list through `sudo env`. Without Full Disk Access for the terminal, macOS privacy protection (TCC) hides some folders even from root. `fs-errors.txt` in each snapshot lists the folders that `find` cannot read. Some install scripts check the file name, so keep the file name of the vendor.

1. Write down the file name of the installer and its SHA-256: `shasum -a 256 /path/to/Installer.pkg`
2. Find your network interface: `route get default | grep interface`. The output names it, for example `en0`.
3. In five separate terminals, start the five captures in the table above. Use your interface in place of `en0`.
4. In System Settings, give a sixth terminal Full Disk Access.
5. In the sixth terminal, make the study folder: `mkdir study`
6. Set the folder list once: the default list plus the browser native-messaging folders.
   `roots="/Library/Application Support:4;/private/etc:3;/usr/local/bin:1;/Applications:1;$HOME/Library/Application Support:2;/Library/Google:4;/Library/Microsoft:4"`
7. Take the first snapshot: `sudo env FOOTPRINT_FS_ROOTS="$roots" ./footprint.sh snapshot 00-before study`
8. Install the package under the file name of the vendor: `sudo installer -pkg /path/to/Installer.pkg -target / -verbose | tee installer.log`
9. Take the second snapshot: `sudo env FOOTPRINT_FS_ROOTS="$roots" ./footprint.sh snapshot 01-after-install study`
10. Stop the `fs_usage` capture with Ctrl-C.
11. Grant the permission in System Settings.
12. Write down the clock time and the app that gets the permission.
13. Take the third snapshot: `sudo env FOOTPRINT_FS_ROOTS="$roots" ./footprint.sh snapshot 02-after-permission study`
14. Use the app for a fixed time, for example 10 minutes.
15. Take the last snapshot: `sudo env FOOTPRINT_FS_ROOTS="$roots" ./footprint.sh snapshot 03-final study`
16. Stop the other captures with Ctrl-C.
17. Export the unified log for the study window: `/usr/bin/log show --info --debug --start "YYYY-MM-DD HH:MM:SS" --predicate 'process IN {"installer", "installd", "package_script_service"} OR senderImagePath CONTAINS[c] "vendor"' > unified.log`
18. Copy the output of the package scripts: `sudo cp /var/log/install.log study/`
19. Make the report: `./footprint.sh report study > study/REPORT.md`

Each snapshot records the macOS version in `meta.txt`.

## How the redaction works

Raw captures hold your username, hostname, LAN addresses and a list of all the software that you run. Nothing raw goes into this repository.

- `tools/redact.py` makes every excerpt under `case-studies/*/evidence/`. It needs only Python 3 and its standard library. It keeps only the lines that its mode allows: vendor processes, vendor sockets, vendor DNS names and structural lines. It replaces each run of dropped lines with `[N unrelated lines removed]`.
- `redact.py` replaces the username with `<user>`, the hostname with `<host>`, private IPs with `<lan-ip>` and other public IPs with `<ip>`. It removes MAC addresses, UUIDs, UDIDs, serial-like tokens and email addresses. With `--mask-unrelated`, it replaces the names of other software in paths and bundle IDs with `<unrelated>`. It shortens runs of spaces, so column padding does not show the length of a masked name.
- The real username and hostname live in `tools/.redact-local.env`, which git ignores. Copy `tools/.redact-local.env.example` to make this file. `REDACT_DENY` in this file lists more strings that must never appear, such as the names of your other software.
- `tools/verify_redaction.sh` scans the files in the git index and fails on any hit. It checks the values from `tools/.redact-local.env`. It also checks for MacBook hostnames, home paths, private, link-local and public IPv4 and IPv6 addresses, MAC addresses, UUIDs and UDIDs. Other checks find per-user temporary folder IDs, serial-like tokens and email addresses. The verifier allows the co-author address of Claude Code and GitHub noreply addresses.
- The verifier also fails on raw capture files and on files over 500 KB. It reports files over 500 KB first and leaves them out of the content checks. `--history` also scans the files and the messages of every commit. The checks for raw files and file size look at the current tree only. CI runs without the deny list, so run `tools/verify_redaction.sh --history` before every push.
- `tests/run.sh` plants each kind of data in a scratch repository and checks that the verifier catches it. It also plants a personal value in a commit message and checks that `--history` catches it. All test values are synthetic. No grep can find a value that is split across string literals. So test code must never copy values from real captures.

## Responsible use

- Observe only software that you have the right to run, on machines that you own or administer.
- Publish observations: file names, labels, versions, log messages and counts. Do not publish vendor binaries, packages or plist files verbatim.
- Report what the data shows. Mark what it cannot show.

## Tests

These commands run in a fresh clone:

```bash
tests/run.sh
python3 tools/check_sentences.py
CI=1 tools/verify_redaction.sh --history
shellcheck footprint.sh tools/*.sh tests/*.sh case-studies/*/evidence/*.sh
```

`CI=1` runs the verifier without a local deny list, as CI does. ShellCheck needs an install, for example `brew install shellcheck`.

`tests/run.sh` needs bash and Python 3. It tests `diff` and `report` on the synthetic snapshots in `tests/fixtures/`. So it needs no root and reads nothing from the system. `tools/check_citations.py` checks that every citation in the evidence opens at the cited raw line. `tools/check_sentences.py` fails on a sentence of more than 25 words in the two README files.

## License

MIT. See [LICENSE](LICENSE).
