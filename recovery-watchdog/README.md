# systemd hardware watchdog

This module enables systemd's hardware watchdog on Raspberry Pi hosts.

## Policy

- Runtime timeout: 30 seconds.
- Shutdown timeout: 2 minutes.

systemd PID 1 feeds the watchdog while the kernel is schedulable. If it cannot,
the Raspberry Pi watchdog resets the host. During a normal reboot, the shutdown
timeout bounds a stalled stop or unmount sequence.

This is a last-resort system layer. It does not probe the network or manage
host-specific services.

## Install

Run as root:

```sh
/home/pi/git/respi/recovery-watchdog/install-hardware-watchdog.sh
```

The installer is idempotent and is invoked by `scripts/deploy.sh` whenever the
host exposes `/dev/watchdog`.
