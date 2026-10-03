# Footprint report

Snapshots: 00-before 01-after 02-later

| Step | receipts | launchd | privhelpers | launchctl | hosts | fs | processes | connections |
|---|---|---|---|---|---|---|---|---|
| 00-before -> 01-after | +2 -0 | +2 -0 | +1 -0 | +3 -0 | +1 -0 | +5 -0 | +2 -1 | +2 -0 |
| 01-after -> 02-later | . | . | . | . | . | . | . | . |

"." means no change.

## 00-before -> 01-after

### receipts.txt

```diff
+ com.example.telemetry
+ com.example.vdi.client
```

### launchd.txt

```diff
+ /Library/LaunchAgents/com.example.telemetry.agent.plist
+ /Library/LaunchDaemons/com.example.telemetryd.plist
```

### privhelpers.txt

```diff
+ com.example.vdi.Helper
```

### launchctl.txt

```diff
+ application.com.example.viewer
+ com.example.telemetryd
+ com.example.vdi.Helper
```

### hosts.txt

```diff
+ 127.0.0.1 example-localhost
```

### fs.txt

```diff
+ /Library/Application Support/Example
+ /Library/Application Support/Example/Telemetry
+ /Library/Application Support/Example/Telemetry/uninstall.sh
+ /private/etc/example
+ /private/etc/example/config.ini
```

### processes.txt

```diff
+ root /usr/local/bin/telemetryd
+ tester /Applications/Example VDI.app/Contents/MacOS/vdi-client
- tester /bin/sleep
```

### connections.txt

```diff
+ vdi-clien tester TCP ->203.0.113.80:443 (ESTABLISHED)
+ vdi-clien tester TCP 127.0.0.1:55615 (LISTEN)
```

## 01-after -> 02-later

No change: receipts.txt launchd.txt privhelpers.txt launchctl.txt hosts.txt fs.txt processes.txt connections.txt
