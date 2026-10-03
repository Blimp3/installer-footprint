#!/usr/bin/env python3
"""Redact raw installer-analysis output before it goes into a public repo.

    redact.py [--mode MODE] [--lines A-B[,C-D]] [--grep REGEX] [--keep-ip IP]...
              [--label NAME] [--dropped FILE] [--no-number] FILE|-
    redact.py --self-test

Selects lines (--lines, then --grep), keeps the ones MODE allows, scrubs
personal data from them and prints them with their original line numbers.
Each run of lines that MODE drops is replaced by "[N unrelated lines removed]".

Modes:
  text  keep every selected line (scrub only)
  proc  ps listings: header, vendor lines, installer/PackageKit lines
  net   lsof listings: header and vendor lines
  dns   DNS logs: lines that contain a vendor domain name
  list  ls/launchctl/pkgutil listings, diffs and reports: structural lines
        (section headers, "dir:" lines, diff hunks), vendor and installer lines

Vendor lines match --vendor (default: the Omnissa/Workspace ONE names).

--mask-unrelated also replaces the names of other software (non-vendor,
non-Apple) in paths and bundle IDs with <unrelated>.

Scrubbing (all modes): username -> <user>, hostname -> <host>, private and
link-local IPs -> <lan-ip>, other public IPs -> <ip> unless given with
--keep-ip, per-user /var/folders/ segments -> <user-tmp>, MAC addresses, UUIDs,
UDIDs, serial-like tokens, CFData byte dumps and email addresses -> <removed>, REDACT_EXTRA strings -> <redacted> (or "text=>replacement").

The real username and hostname come from tools/.redact-local.env (git-ignored,
see tools/.redact-local.env.example). --dropped FILE appends every dropped line
and every public-IP or serial replacement, unredacted, for local review only.
"""
import argparse
import io
import ipaddress
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL_ENV = os.path.join(HERE, ".redact-local.env")

# Default vendor pattern: the Omnissa Horizon Client case study. Override with --vendor.
VENDOR_DEFAULT = r"omnissa|horizon|workspaceone|airwatch|ws1|deem|vmware|view-localhost|html5videoplayer"
VENDOR = re.compile(VENDOR_DEFAULT, re.I)
INSTALLER = re.compile(r"\b(installer|installd|system_installd|package_script_service)\b|PackageKit", re.I)
VENDOR_DOMAIN = re.compile(r"[\w.-]*(omnissa|vmware|workspaceone|airwatch|awmdm|ws1|horizon|deem)[\w-]*(\.[\w-]+)*\.[a-z]{2,}", re.I)
STRUCTURAL = re.compile(r"^(={2,}|#{2,}|-{2,}|\d+(,\d+)?[acd]\d+(,\d+)?$|/[^ ].*:$|```|\| )")
PS_HEADER = re.compile(r"^\s*PID\s+PPID\s")

IPV4 = re.compile(r"(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?!\d)")
IPV6 = re.compile(r"(?<![\w:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![\w:])")
MAC = re.compile(r"(?<![0-9A-Fa-f:-])(?:(?:[0-9A-Fa-f]{1,2}:){5}|(?:[0-9A-Fa-f]{1,2}-){5})[0-9A-Fa-f]{1,2}(?![0-9A-Fa-f:-])")
UUID = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(?![0-9A-Fa-f])")
UDID = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}(?![0-9A-Fa-f])")
SERIAL = re.compile(r"\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{10,12}\b")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@(?![0-9]x\.)[A-Za-z0-9.-]+\.(?!(?:png|jpe?g|gif|pdf|plist|json|tiff?|heic)\b)[A-Za-z]{2,}")
VARFOLDERS = re.compile(r"(?:/var)?/folders/[^/\s]{2}/[^/\s]{20,}/")  # per-user temp dir, also front-cut
# --mask-unrelated: names of other software in paths and bundle IDs
APP_PATH = re.compile(r"(/(?:Application Support|Applications|Containers|Group Containers|Caches|Preferences|Logs)/)"
                      r"((?:[^/\s,;:{}\[\]'\"]|\s(?=[^\s/]))+(?:/(?:[^/\s,;:{}\[\]'\"]|\s(?=[^\s/]))*)*)")
BUNDLE_ID = re.compile(r"\b(?:com|net|org|io|at|it|ch|de|co|app|dev|me|us|uk|eu|fr|nl|se|jp)\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9_-]+)+")
APPLE = re.compile(r"^(?:com\.apple\.|Apple\b)")
CFDATA = re.compile(r"bytes = 0x[0-9A-Fa-f]+(?: [0-9A-Fa-f]+)*(?: \.\.\.(?: [0-9A-Fa-f]+)*)?")  # CFData dumps: opaque tokens
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
CGNAT = ipaddress.ip_network((0x64400000, 10))  # carrier-grade NAT, RFC 6598


def load_local_env(path=LOCAL_ENV):
    vals = {}
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    vals[k.strip()] = v.strip().strip("'\"")
    return vals


class Scrubber:
    def __init__(self, user="", host="", extra=(), keep_ips=(), keep_tokens=(), mask_unrelated=False):
        self.keep_ips = set(keep_ips)
        self.mask_unrelated = mask_unrelated
        self.keep_tokens = set(keep_tokens)
        self.log = []  # (kind, before, after) for replacements worth reviewing
        self.words = []
        if host:
            parts = [re.escape(p) for p in re.split(r"[-\s]+", host) if p]
            self.words.append((re.compile(r"[-\s]?".join(parts) + r"(\.local|\.lan|\.home)?", re.I), "<host>"))
        if user:
            self.words.append((re.compile(r"(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])", re.I), "<user>"))
        for e in extra:  # "text" -> <redacted>, "text=>replacement" -> replacement
            text, _, rep = e.partition("=>")
            if text:
                self.words.append((re.compile(re.escape(text), re.I), rep or "<redacted>"))

    def _words(self, line):
        for pat, rep in self.words:
            line = pat.sub(lambda m, r=rep: r, line)  # literal replacement, no backrefs
        return line

    def _ip(self, m, v6=False):
        text = m.group(0)
        try:
            ip = ipaddress.ip_address(text)
        except ValueError:
            return text  # a timestamp or version string, not an address
        if text in self.keep_ips or ip.is_loopback or ip.is_unspecified or ip.is_multicast:
            return text
        if str(ip) == "255.255.255.255":
            return text
        if ip.is_private or ip.is_link_local or (not v6 and ip in CGNAT):
            return "<lan-ip>"
        self.log.append(("public-ip", text, "<ip>"))
        return "<ip>"

    def _serial(self, m):
        if m.group(0) in self.keep_tokens:
            return m.group(0)
        self.log.append(("serial-like", m.group(0), "<removed>"))
        return "<removed>"

    def _unrelated(self, text):
        return not (VENDOR.search(text) or APPLE.match(text))

    def scrub(self, line):
        line = CONTROL.sub("", line)
        if self.mask_unrelated:
            line = APP_PATH.sub(lambda m: m.group(0) if not self._unrelated(m.group(2)) else m.group(1) + "<unrelated>", line)
            line = BUNDLE_ID.sub(lambda m: "<unrelated>" if self._unrelated(m.group(0)) else m.group(0), line)
        line = EMAIL.sub("<removed>", line)
        line = self._words(line)
        line = VARFOLDERS.sub(lambda m: m.group(0)[: m.group(0).index("/folders/")] + "/folders/<user-tmp>/", line)
        line = CFDATA.sub("bytes = <removed>", line)
        line = MAC.sub("<removed>", line)
        line = UUID.sub("<removed>", line)
        line = UDID.sub("<removed>", line)
        line = IPV6.sub(lambda m: self._ip(m, v6=True), line)
        line = IPV4.sub(self._ip, line)
        return SERIAL.sub(self._serial, line)


def keep(mode, line):
    if mode == "text":
        return True
    if mode == "proc":
        return bool(PS_HEADER.match(line) or VENDOR.search(line) or INSTALLER.search(line))
    if mode == "net":
        return line.startswith("COMMAND ") or bool(VENDOR.search(line))
    if mode == "dns":
        return bool(VENDOR_DOMAIN.search(line))
    if mode == "list":
        return not line.strip() or bool(STRUCTURAL.match(line) or VENDOR.search(line) or INSTALLER.search(line))
    raise ValueError(mode)


def parse_ranges(spec):
    ranges = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        ranges.append((int(a), int(b or a)))
    return ranges


def redact(lines, mode="text", ranges=None, grep=None, scrubber=None, number=True):
    """Return (output_lines, dropped_records) for an iterable of raw lines."""
    scrubber = scrubber or Scrubber()
    grep_re = re.compile(grep, re.I) if grep else None
    out, dropped, run = [], [], 0
    width = 6 if number else 0

    def flush():
        nonlocal run
        if run:
            out.append(f"{'':>{width}}  [{run} unrelated line{'s' if run > 1 else ''} removed]" if number
                       else f"[{run} unrelated line{'s' if run > 1 else ''} removed]")
            run = 0

    for n, raw in enumerate(lines, 1):
        raw = raw.rstrip("\n")
        if ranges and not any(a <= n <= b for a, b in ranges):
            continue
        if grep_re and not grep_re.search(raw):
            continue
        if not keep(mode, raw):
            run += 1
            dropped.append(f"{n}: dropped: {raw}")
            continue
        flush()
        before = len(scrubber.log)
        text = re.sub(r" {2,}", "  ", scrubber.scrub(raw))  # fixed gaps: padding must not show a hidden name's length
        for kind, a, b in scrubber.log[before:]:
            dropped.append(f"{n}: replaced {kind}: {a} -> {b}")
        out.append(f"{n:>{width}}  {text}" if number else text)
    flush()
    if mode == "list":  # collapse runs of blank lines
        out = [l for i, l in enumerate(out) if l.strip() or (i and out[i - 1].strip())]
    return out, dropped


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("file", nargs="?")
    p.add_argument("--mode", default="text", choices=["text", "proc", "net", "dns", "list"])
    p.add_argument("--lines")
    p.add_argument("--grep")
    p.add_argument("--keep-ip", action="append", default=[])
    p.add_argument("--keep-token", action="append", default=[], help="serial-like token to keep (e.g. a public team ID)")
    p.add_argument("--mask-unrelated", action="store_true", help="replace non-vendor, non-Apple app names in paths and bundle IDs with <unrelated>")
    p.add_argument("--vendor", help=f"regex for vendor lines (default: {VENDOR_DEFAULT})")
    p.add_argument("--label")
    p.add_argument("--dropped")
    p.add_argument("--no-number", action="store_true")
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args(argv)
    if a.self_test:
        return self_test()
    if not a.file:
        p.error("FILE is required")
    if a.vendor:
        global VENDOR, VENDOR_DOMAIN
        VENDOR = re.compile(a.vendor, re.I)
        VENDOR_DOMAIN = re.compile(r"[\w.-]*(" + a.vendor + r")[\w-]*(\.[\w-]+)*\.[a-z]{2,}", re.I)

    env = load_local_env()
    if not env.get("REDACT_USER") or not env.get("REDACT_HOST"):
        sys.exit(f"redact.py: set REDACT_USER and REDACT_HOST in {LOCAL_ENV} (see .redact-local.env.example)")
    extra = [x.strip() for x in env.get("REDACT_EXTRA", "").split(",")]
    scrubber = Scrubber(env["REDACT_USER"], env["REDACT_HOST"], extra, a.keep_ip, a.keep_token, a.mask_unrelated)

    if a.file == "-":
        src = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="replace")
    else:
        src = open(a.file, encoding="utf-8", errors="replace")
    with src:
        out, dropped = redact(src, a.mode, parse_ranges(a.lines) if a.lines else None, a.grep, scrubber, not a.no_number)

    label = a.label or ("stdin" if a.file == "-" else os.path.basename(a.file))
    sel = "".join(f" {k}={v}" for k, v in (("lines", a.lines), ("grep", a.grep)) if v)
    print(scrubber.scrub(f"# source: {label} | mode={a.mode}{sel} | redacted by tools/redact.py"))
    print("\n".join(out))
    if a.dropped and dropped:
        with open(a.dropped, "a") as f:
            f.write(f"### {label} (mode={a.mode}{sel})\n" + "\n".join(dropped) + "\n")
    return 0


def self_test():
    # All test values are synthetic. None comes from real captures. Values that
    # look like personal data are built at runtime so tools/verify_redaction.sh
    # never sees them as literals.
    user, host = "alex", "Alexs-" + "MacBook-" + "Air"
    lan = ".".join(["192", "168", "77", "23"])
    s = Scrubber(user, host, ["SecretCo", "old-name.pkg=><local-pkg>", "a\\b=>x"],
                 keep_ips=["203.0.113.80"], keep_tokens=["AB12" + "CD34EF"])
    sc = s.scrub
    assert sc("/Users/" + user + "/Library") == "/Users/<user>/Library"
    assert sc("Alexs is here, alex_x") == "Alexs is here, <user>_x"
    assert sc(host + ".local installer[1]: ok") == "<host> installer[1]: ok"
    assert sc("Alexs MacBook Air") == "<host>"
    assert sc(f"TCP {lan}:12345->203.0.113.80:443") == "TCP <lan-ip>:12345->203.0.113.80:443"
    assert sc(f"IP {lan}.23456 > {lan[:-2]}1.53:") == "IP <lan-ip>.23456 > <lan-ip>.53:"
    assert sc("to " + ".".join(["11", "22", "33", "44"]) + ":443") == "to <ip>:443"
    assert sc("10." + "0.0.7 and 172." + "20.1.1 and 100." + "100.1.1") == "<lan-ip> and <lan-ip> and <lan-ip>"
    assert sc("127.0.0.1 view-localhost 255.255.255.255 224.0.0.251") == "127.0.0.1 view-localhost 255.255.255.255 224.0.0.251"
    assert sc("pkg-31.4.0.7012 v4321.500.6.1.1 9.2.0-1234567890") == "pkg-31.4.0.7012 v4321.500.6.1.1 9.2.0-1234567890"
    assert sc("[" + ":".join(["fd12", "3456", "789a", "1"]) + "::5]:12345 at 09:41:00.12 ::1") == "[<lan-ip>]:12345 at 09:41:00.12 ::1"
    assert sc("window 17:18:10-17:29:38 CEST") == "window 17:18:10-17:29:38 CEST"
    assert sc("en0 " + ":".join(["a4", "83", "e7", "00", "11", "22"])) == "en0 <removed>"
    assert sc("en1 " + "-".join(["2", "b", "c", "d", "e", "f"])) == "en1 <removed>"
    assert sc("id " + "-".join(["11111111", "2222", "4333", "8444", "5555" + "55555555"])) == "id <removed>"
    assert sc("evt_journal_" + "-".join(["11111111", "2222", "4333", "8444", "5555" + "55555555"]) + "_1.toc") == "evt_journal_<removed>_1.toc"
    assert sc("udid " + "00008103-" + "001234560A12001E") == "udid <removed>"
    assert sc("serial " + "C02" + "XK1ZJG5H" + " ok") == "serial <removed> ok"
    assert sc("WORKSPACEONE 1234567890 ok") == "WORKSPACEONE 1234567890 ok"
    assert sc("mail " + "someone" + "@" + "example.org") == "mail <removed>"
    assert sc("icon" + "@" + "2x.png") == "icon" + "@" + "2x.png"
    assert sc("SecretCo.app") == "<redacted>.app"
    assert sc("/tmp/old-name.pkg ok") == "/tmp/<local-pkg> ok"
    assert sc("/tmp/a" + "\\" + "b") == "/tmp/x"
    assert sc("/private/var/folders/x8/abc_12" + "d" * 20 + "/T/a.lock") == "/private/var/folders/<user-tmp>/T/a.lock"
    assert sc("/folders/qq/" + "q" * 28 + "/C/x") == "/folders/<user-tmp>/C/x"
    assert sc("team:(AB12" + "CD34EF)") == "team:(AB12" + "CD34EF)"
    assert sc("bell\x07 and tab\tok") == "bell and tab\tok"
    assert sc("Token = {length = 32, bytes = 0x0a1b2c3d 4e5f6a7b ... 8c9d0e1f }") == "Token = {length = 32, bytes = <removed> }"

    m = Scrubber(user, host, mask_unrelated=True).scrub
    assert m("open /Users/" + user + "/Library/Application Support/Some App/x.db   0.1 ws1etlm.1") == "open /Users/<user>/Library/Application Support/<unrelated>   0.1 ws1etlm.1"
    assert m("binary_path=/Applications/Term.app/Contents/MacOS/term}, x") == "binary_path=/Applications/<unrelated>}, x"
    assert m("/Applications/Omnissa Horizon Client.app/Contents/MacOS/horizon-client") == "/Applications/Omnissa Horizon Client.app/Contents/MacOS/horizon-client"
    assert m("Sub:{net.example.term} com.apple.TCC com.ws1.deemd org.cef.html5videoplayer") == "Sub:{<unrelated>} com.apple.TCC com.ws1.deemd org.cef.html5videoplayer"
    assert m("/Library/Application Support/Apple/AssetCache") == "/Library/Application Support/Apple/AssetCache"
    assert m("WrData /Users/" + user + "/Library/Application Support/Some App (beta)/data/x.sqlite   0.1 W deemd") == "WrData /Users/<user>/Library/Application Support/<unrelated>   0.1 W deemd"

    out, dropped = redact(["  PID  PPID USER COMM", "  1 0 root /sbin/launchd", "  7 1 root /usr/local/bin/deemd",
                           "  8 1 alex /usr/libexec/x", "  9 1 root /System/Library/PrivateFrameworks/PackageKit.framework/installd"],
                          mode="proc", scrubber=s, number=False)
    assert out == ["  PID  PPID USER COMM", "[1 unrelated line removed]", "  7 1 root /usr/local/bin/deemd",
                   "[1 unrelated line removed]", "  9 1 root /System/Library/PrivateFrameworks/PackageKit.framework/installd"], out
    assert len(dropped) == 2
    out, _ = redact(["  8     1 alex             /usr/local/bin/ws1etlmu"], mode="proc", scrubber=s, number=False)
    assert out == ["  8  1 <user>  /usr/local/bin/ws1etlmu"], out  # padding no longer shows the name length
    out, _ = redact(["A? api.example.com.", "A? cdn.omnissa.com.", "A? x.example.net."], mode="dns", scrubber=s, number=False)
    assert out == ["[1 unrelated line removed]", "A? cdn.omnissa.com.", "[1 unrelated line removed]"], out
    out, _ = redact(["== receipts.txt (+2 -0)", "+ com.ws1.Deem", "+ com.other.app", "/Library/LaunchAgents:"], mode="list", scrubber=s, number=False)
    assert out == ["== receipts.txt (+2 -0)", "+ com.ws1.Deem", "[1 unrelated line removed]", "/Library/LaunchAgents:"], out
    out, _ = redact(["a", "b", "c", "d"], ranges=parse_ranges("2-3"), scrubber=s)
    assert out == ["     2  b", "     3  c"], out
    print("redact.py self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
