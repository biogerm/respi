# Network Recovery Controller

This controller is shared by LivingRoom, vpngateway, and kitchenpi.

It declares a management outage only when every configured link fails carrier,
address, default-route, or gateway data-plane checks for 180 seconds. A healthy
backup Wi-Fi link prevents a host-level reset.

The controller resets dhcpcd and configured interfaces once, then waits 120
seconds. If still unavailable, it requests one normal reboot. A later boot
suppresses repeated automatic reboots for the same incident and only retries
network recovery every ten minutes.

A separate systemd timer runs guard mode. If the main recovery process remains
marked active after its deadline and all links are still down, the guard submits
the normal reboot request. The systemd hardware watchdog is the final fallback
when PID 1, the kernel, or that reboot sequence cannot progress.

Homebridge and OpenVPN retain their own health checks, but they no longer reset
interfaces, dhcpcd, or the host. Kitchenpi keeps its existing observer and
scheduled reboots unchanged.
