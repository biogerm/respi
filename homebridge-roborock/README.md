# Homebridge Roborock A23 Worklog

This directory records the Homebridge Roborock A23 troubleshooting work.
It intentionally contains no Xiaomi token, password, or Homebridge secret.

## Current Network

- Homebridge Pi: `192.168.0.180`
- ASUS RT-AC68U WAN/main-network address: `192.168.0.25`
- ASUS LAN address: `192.168.1.1`
- Roborock S7+ China model A23: `192.168.1.72`
- Homebridge accessory name: `BB8`
- Homebridge Roborock plugin: `homebridge-xiaomi-roborock-vacuum@0.20.1`

The Roborock is behind the ASUS LAN. The ASUS is an OpenVPN client router,
not a VPN server.

## Known Results

- ASUS LAN side can reach the Roborock at `192.168.1.72`.
- A minimal ASUS-side miIO probe successfully received an application-level
  Roborock response:

```json
{"id":1,"result":"unknown_method","exe_time":11}
```

This proves the Roborock receives encrypted miIO command packets from the
ASUS LAN side, and the token/encryption path is valid.

The failing path is therefore likely the Pi-to-ASUS-to-Roborock forwarding
path, not the token itself.

- A UDP relay on ASUS listening on `192.168.0.25:54322` successfully relayed
  Pi-originated miIO traffic to Roborock `192.168.1.72:54321`.
- Homebridge can read BB8 state through that relay after the plugin passes the
  configured `port` option to the miio library.

## Safety Rule

When outside the home network, do not run network tests. The user explicitly
allowed SSH and ping only. Ask before any other active network test.

## Next Session Checklist

Current working setup:

1. ASUS runs `/tmp/asus_udp_relay_nolibc`.
2. ASUS INPUT allows `192.168.0.180 -> udp/54322`.
3. Homebridge BB8 config uses `ip: 192.168.0.25` and `port: 54322`.
4. Pi runs `roborock-relay-watchdog.timer` to redeploy/restart the ASUS relay.

## Files

- `patches/PATCHED_FILES.md`: installed plugin files that were patched on Pi.
- `scripts/sync-patched-plugin-files.sh`: run on Pi to copy the live patched
  plugin files into this repo.
- `relay/SOLUTION.md`: relay and Pi-side monitor design.
- `relay/tools/`: small ASUS-side test sources used during diagnosis.
- `scripts/roborock-relay-watchdog.sh`: Pi-side ASUS relay watchdog.
- `systemd/`: service and timer units for the watchdog.
