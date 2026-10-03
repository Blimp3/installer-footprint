# Case study: the Omnissa Horizon Client installer on macOS

Every claim cites a fact ID in [evidence/FACTS.md](evidence/FACTS.md). Facts from the captures cite the raw lines, mostly through redacted excerpts. Facts with an `OWN` ID are reported by the owner, not taken from the captures. Setup, Findings, Phase 2 and 3, What this means, Limits and Reproduce it follow after the owner's review of the facts.

## Summary

**Not malware. A legitimate vendor installer that also installs a Workspace ONE telemetry and experience-management stack with root-level persistence.**

- Installed: the Omnissa Horizon Client 8.17.0 package, which also installs Workspace ONE Deem 25.09.00.701 with an installer helper and the Workspace ONE Endpoint Telemetry Service 25.9.0.5699 (SET-20, SET-21, R1-19, P1-19).
- Added: three LaunchDaemons and one privileged helper, all owned by root, with the `deemd` and `ws1etlm` processes running as root. Also two LaunchAgents, the line `127.0.0.1 view-localhost` at the top of `/etc/hosts`, and configuration under `/etc/workspaceone` (R1-24, R1-28, R1-32, R1-93, R1-40, R1-46).
- Full Disk Access: the owner reports granting it in run 2, in the second step after the install. The app and the time are not confirmed. The captured logs record no Full Disk Access grant, so this study draws no conclusion about behaviour after Full Disk Access (OWN-03, P2-20).
- For a user or an IT admin: installing the Horizon Client also installs and configures a telemetry service, which you can find by its `com.ws1.*` package receipts and launchd labels (R1-19, R1-24, R1-28).

## Why this study

This is an independent case study, prompted by a concern that the installer was malware. The vendor was not contacted (OWN-01).

The concern was treated as a hypothesis and tested first, with a static analysis of the package. The owner's static analysis found a legitimate Omnissa package. Its outputs are not yet in this repository (OWN-02, [Static analysis](#static-analysis)). The hypothesis was rejected.

The behavioural review went ahead anyway, to record what the installer adds to a Mac in practice. It has two runs on 25 June 2026. Run 1 is the install. Run 2 has three steps: install, a Full Disk Access step, and a short observation (OWN-03, OWN-07).

During the static analysis, the owner gave the run 1 package file a local name (OWN-06). The name is withheld here, but the fact matters: the vendor's postinstall script read the file name and chose its default configuration because of it (R1-84).

## Static analysis

TODO(owner): add static-analysis evidence. The owner's static analysis was done before the captures, and its outputs are not in the raw folders. Searched for and not found:

- `codesign -dv` or `codesign --verify` output
- `spctl --assess` output
- `pkgutil --check-signature` output
- The certificate chain of the vendor signatures (Developer ID Installer or Developer ID Application, organization name)
- SHA-256 or other hashes of the `.pkg` and the `.dmg` (SET-29)
- VirusTotal or other third-party scanner reports
- A logged notarization check of the Horizon Client package, the Endpoint Telemetry package or the `.dmg`. The log filter of the captures does not select lines that name only these files, so this absence does not show that no check took place (SET-86).

The exact search commands are in [evidence/FACTS.md](evidence/FACTS.md), Part A. Signing checks that macOS logged during the captured installs belong to the behavioural study. They are the Part B facts with the category `[signature]`.
