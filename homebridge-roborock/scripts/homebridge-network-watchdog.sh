#!/bin/sh
set -eu

SERVICE="homebridge.service"
TAG="homebridge-service-watchdog"
STATE_DIR="/var/lib/homebridge-service-watchdog"
RESTART_MARKER="$STATE_DIR/restart-requested"
NETWORK_RECOVERY="/run/pi-network-recovery-watchdog/recovery-active"
DEFER_MARKER="$STATE_DIR/network-recovery-deferred"
RESTART_GRACE_SECONDS=180

log() {
    logger -t "$TAG" "$*" || true
}

boot_id() {
    cat /proc/sys/kernel/random/boot_id
}

field() {
    [ -r "$1" ] && sed -n "${2:-1}p" "$1" 2>/dev/null || true
}

if [ "${1:-run}" = check ]; then
    if systemctl is-active --quiet "$SERVICE"; then
        printf 'homebridge=healthy\n'
        exit 0
    fi
    printf 'homebridge=inactive\n'
    exit 1
fi

mkdir -p "$STATE_DIR"
if systemctl is-active --quiet "$SERVICE"; then
    rm -f "$RESTART_MARKER"
    exit 0
fi

if [ -f "$NETWORK_RECOVERY" ]; then
    if [ ! -f "$DEFER_MARKER" ]; then
        : > "$DEFER_MARKER"
        log "$SERVICE is inactive while generic network recovery is active; deferring restart"
    fi
    exit 0
fi

rm -f "$DEFER_MARKER"
now=$(date +%s)
last_boot=$(field "$RESTART_MARKER" 2)
last_epoch=$(field "$RESTART_MARKER" 1)
if [ "$last_boot" = "$(boot_id)" ] && [ -n "$last_epoch" ] &&
    [ $((now - last_epoch)) -lt "$RESTART_GRACE_SECONDS" ]; then
    exit 0
fi

{
    date +%s
    boot_id
} > "$RESTART_MARKER"
log "$SERVICE is inactive; requesting one service restart"
systemctl restart "$SERVICE" || log "restart command returned an error"
