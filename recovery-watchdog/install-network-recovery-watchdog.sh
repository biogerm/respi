#!/bin/sh
set -eu

[ "$(id -u)" = 0 ] || {
    echo "This script must run as root." >&2
    exit 1
}

module_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$module_dir/.." && pwd)
profile_name=${1:-$(hostname)}
profile="$module_dir/profiles/$profile_name.conf"
[ -r "$profile" ] || {
    echo "No recovery profile exists for host: $profile_name" >&2
    exit 1
}

install -D -m 0755 "$module_dir/pi-network-recovery-watchdog" \
    /usr/local/sbin/pi-network-recovery-watchdog
install -D -m 0644 "$profile" /etc/default/pi-network-recovery-watchdog
install -D -m 0644 "$module_dir/systemd/pi-network-recovery-watchdog.service" \
    /etc/systemd/system/pi-network-recovery-watchdog.service
install -D -m 0644 "$module_dir/systemd/pi-network-recovery-watchdog.timer" \
    /etc/systemd/system/pi-network-recovery-watchdog.timer
install -D -m 0644 "$module_dir/systemd/pi-network-recovery-reboot-guard.service" \
    /etc/systemd/system/pi-network-recovery-reboot-guard.service
install -D -m 0644 "$module_dir/systemd/pi-network-recovery-reboot-guard.timer" \
    /etc/systemd/system/pi-network-recovery-reboot-guard.timer

case "$profile_name" in
    LivingRoom)
        systemctl stop homebridge-network-watchdog.timer || true
        systemctl stop homebridge-network-watchdog.service || true
        install -D -m 0755 "$source_root/homebridge-roborock/scripts/homebridge-network-watchdog.sh" \
            /usr/local/sbin/homebridge-network-watchdog
        install -D -m 0644 "$source_root/homebridge-roborock/systemd/homebridge-network-watchdog.service" \
            /etc/systemd/system/homebridge-network-watchdog.service
        install -D -m 0644 "$source_root/homebridge-roborock/systemd/homebridge-network-watchdog.timer" \
            /etc/systemd/system/homebridge-network-watchdog.timer
        ;;
    vpngateway)
        systemctl stop openvpn-uk-route-watchdog.timer || true
        systemctl stop openvpn-uk-route-watchdog.service || true
        install -D -m 0755 "$source_root/vpngateway/openvpn-uk-route-watchdog" \
            /usr/local/sbin/openvpn-uk-route-watchdog
        install -D -m 0644 "$source_root/vpngateway/openvpn-uk-route-watchdog.service" \
            /etc/systemd/system/openvpn-uk-route-watchdog.service
        install -D -m 0644 "$source_root/vpngateway/openvpn-uk-route-watchdog.timer" \
            /etc/systemd/system/openvpn-uk-route-watchdog.timer
        ;;
esac

systemctl daemon-reload
systemctl enable pi-network-recovery-watchdog.timer
systemctl start pi-network-recovery-watchdog.timer
systemctl enable pi-network-recovery-reboot-guard.timer
systemctl start pi-network-recovery-reboot-guard.timer

case "$profile_name" in
    LivingRoom) systemctl enable homebridge-network-watchdog.timer; systemctl start homebridge-network-watchdog.timer ;;
    vpngateway) systemctl enable openvpn-uk-route-watchdog.timer; systemctl start openvpn-uk-route-watchdog.timer ;;
esac

systemctl is-active pi-network-recovery-watchdog.timer
systemctl is-active pi-network-recovery-reboot-guard.timer
