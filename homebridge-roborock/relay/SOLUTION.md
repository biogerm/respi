# ASUS UDP Relay Plan

## Problem

Homebridge on Pi `192.168.0.180` talks to ASUS `192.168.0.25`, while the
Roborock is behind ASUS on `192.168.1.72`.

ASUS port forwarding can pass at least the miIO handshake, but encrypted command
packets did not reliably produce replies when sent from the Pi through the
port-forwarding/NAT path.

ASUS itself can send a valid encrypted miIO command to the Roborock and receive
an application-level error reply. This means token and encryption are valid from
the ASUS LAN side.

## Relay Principle

Run a tiny UDP relay process on ASUS:

```text
Homebridge/Pi 192.168.0.180
    -> ASUS 192.168.0.25:54322
        -> relay process
            -> Roborock 192.168.1.72:54321
            <- Roborock reply
        <- relay process
    <- Homebridge/Pi
```

The relay does not decrypt miIO packets. It only forwards UDP datagrams and
remembers the Pi-side source address for replies.

The important behavioral difference from kernel port forwarding is that the
Roborock sees traffic from the ASUS LAN-side host, normally `192.168.1.1`, which
matches the already successful ASUS-side miIO probe path.

## Persistence Strategy

ASUS stock firmware may not support Merlin-style `/jffs/scripts/services-start`
hooks. Do not assume it does.

Instead, run a watchdog on Pi `192.168.0.180`:

1. Every minute, SSH to `biogerm@192.168.0.25`.
2. Check whether the ASUS relay process is running.
3. Check whether ASUS INPUT allows `192.168.0.180 -> udp/54322`.
4. If missing, copy the relay binary to ASUS `/tmp`.
5. Start the relay again.
6. Log failures and restarts through systemd/journald on the Pi.

This makes ASUS `/tmp` acceptable. If ASUS reboots or clears `/tmp`, the Pi
watchdog redeploys the relay.

## SNAT

If the relay is used, the earlier manual SNAT rule should not be needed:

```text
iptables -t nat -I POSTROUTING 1 \
  -p udp -s 192.168.0.180 -d 192.168.1.72 --dport 54321 \
  -j SNAT --to-source 192.168.1.1
```

That rule was useful for kernel NAT experiments. A user-space relay creates a
new ASUS-originated UDP socket to the Roborock, so Roborock already sees ASUS as
the source.

The current relay listens on `192.168.0.25:54322`, so it does not conflict with
the existing ASUS `54321` port forwarding rule.

The required ASUS INPUT rule is:

```sh
/usr/sbin/iptables -I INPUT 1 \
  -p udp -s 192.168.0.180 --dport 54322 \
  -j ACCEPT
```

The watchdog maintains this rule.

## Expected Failure Modes

- ASUS reboots: relay disappears from `/tmp`; Pi watchdog redeploys it.
- Relay crashes: Pi watchdog restarts it within the timer interval.
- ASUS SSH unreachable: Homebridge control may remain broken until SSH recovers.
- Roborock IP changes: relay target must be updated. Keep Roborock fixed at
  `192.168.1.72` via ASUS DHCP reservation.

## Verified

- Pi-side read-only `get_status` through the relay succeeded.
- Homebridge restarted with BB8 `port: 54322` and read state, fan speed,
  battery, serial number, and firmware successfully.
