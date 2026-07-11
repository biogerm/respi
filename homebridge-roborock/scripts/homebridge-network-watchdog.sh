#!/bin/sh
set -eu

IFACE="eth0"
LOCAL_ADDRESS="192.168.0.180"
GATEWAY="192.168.0.1"
NETWORK_SERVICE="dhcpcd.service"
HOMEBRIDGE_SERVICE="homebridge.service"
SYSLOG="/var/log/syslog"
TAG="homebridge-network-watchdog"

STATE_DIR="/var/lib/homebridge-network-watchdog"
NETWORK_REBOOT_MARKER="$STATE_DIR/network-reboot-requested"
NETWORK_RETRY_MARKER="$STATE_DIR/last-network-retry"
HOMEBRIDGE_RESTART_MARKER="$STATE_DIR/homebridge-restarted"
HOMEBRIDGE_REBOOT_MARKER="$STATE_DIR/homebridge-reboot-requested"
TRACE_LOG="/var/log/homebridge-network-watchdog-trace.log"
TRACE_MAX_BYTES=2097152

HOME_LOG_MAX_AGE=300
HOMEBRIDGE_RESTART_WAIT=180
POST_REBOOT_RETRY_SECONDS=1800
RESET_WAIT_ATTEMPTS=6
RESET_WAIT_SECONDS=5

log() {
    logger -t "$TAG" "$*"
}

read_epoch() {
    if [ -f "$1" ]; then
        sed -n '1p' "$1" 2>/dev/null || printf '0\n'
    else
        printf '0\n'
    fi
}

current_boot_id() {
    cat /proc/sys/kernel/random/boot_id
}

router_maintenance_window() {
    # The main router restarts daily around 05:51 local time.
    case "$(date +%H%M)" in
        0548|0549|055[0-9]|0600) return 0 ;;
    esac
    return 1
}

network_fault_reason() {
    if [ ! -d "/sys/class/net/$IFACE" ]; then
        printf 'interface-missing\n'
        return
    fi

    carrier=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || printf '0')
    if [ "$carrier" != "1" ]; then
        printf 'carrier-down\n'
        return
    fi

    if ! ip link show dev "$IFACE" 2>/dev/null | grep -q "state UP"; then
        printf 'interface-down\n'
        return
    fi

    if ! ip -4 addr show dev "$IFACE" scope global 2>/dev/null |
        grep -Fq "inet $LOCAL_ADDRESS/"; then
        printf 'address-missing\n'
        return
    fi

    if ! ip -4 route show default 2>/dev/null |
        grep -Fq "via $GATEWAY dev $IFACE"; then
        printf 'default-route-missing\n'
        return
    fi

    if ! ping -c 1 -W 1 "$GATEWAY" >/dev/null 2>&1; then
        printf 'gateway-unreachable\n'
        return
    fi

    printf 'healthy\n'
}

homebridge_fault_reason() {
    if ! systemctl is-active --quiet "$HOMEBRIDGE_SERVICE"; then
        printf 'service-inactive\n'
        return
    fi

    if [ ! -r "$SYSLOG" ]; then
        printf 'syslog-unreadable\n'
        return
    fi

    line=$(awk '/homebridge\[[0-9]+\]:/ { last=$0 } END { print last }' "$SYSLOG")
    if [ -z "$line" ]; then
        printf 'homebridge-log-missing\n'
        return
    fi

    stamp=$(printf '%s\n' "$line" | cut -c1-15)
    then=$(date -d "$stamp" +%s 2>/dev/null || printf '0')
    now=$(date +%s)

    if [ "$then" -le 0 ] || [ "$now" -lt "$then" ]; then
        printf 'homebridge-log-time-invalid\n'
        return
    fi

    if [ $((now - then)) -gt "$HOME_LOG_MAX_AGE" ]; then
        printf 'homebridge-log-stale\n'
        return
    fi

    printf 'healthy\n'
}

rotate_trace_log() {
    [ -f "$TRACE_LOG" ] || return 0
    size=$(wc -c < "$TRACE_LOG" 2>/dev/null || printf '0')
    [ "$size" -lt "$TRACE_MAX_BYTES" ] && return 0

    rm -f "$TRACE_LOG.3"
    [ ! -f "$TRACE_LOG.2" ] || mv "$TRACE_LOG.2" "$TRACE_LOG.3"
    [ ! -f "$TRACE_LOG.1" ] || mv "$TRACE_LOG.1" "$TRACE_LOG.2"
    mv "$TRACE_LOG" "$TRACE_LOG.1"
}

trace_snapshot() {
    label=$1
    network_reason=$(network_fault_reason)
    homebridge_reason=$(homebridge_fault_reason)
    rotate_trace_log || log "could not rotate trace log"

    {
        printf '\n===== watchdog trace: %s =====\n' "$label"
        date -R
        printf 'boot_id=%s\n' "$(current_boot_id)"
        printf 'network_reason=%s\n' "$network_reason"
        printf 'homebridge_reason=%s\n' "$homebridge_reason"

        printf '\n-- resources --\n'
        uptime || true
        free -m || true
        df -h / /var/log || true
        vcgencmd get_throttled 2>/dev/null || true
        vcgencmd measure_temp 2>/dev/null || true

        printf '\n-- network --\n'
        for item in carrier operstate address mtu speed duplex; do
            path="/sys/class/net/$IFACE/$item"
            [ ! -r "$path" ] || printf '%s=%s\n' "$item" "$(cat "$path" 2>/dev/null || true)"
        done
        ip -d -s link show dev "$IFACE" 2>/dev/null || true
        ip -4 addr show dev "$IFACE" 2>/dev/null || true
        ip -4 route show table all 2>/dev/null || true
        ip neigh show dev "$IFACE" 2>/dev/null || true

        printf '\n-- service state --\n'
        systemctl is-active "$NETWORK_SERVICE" 2>/dev/null || true
        systemctl is-active "$HOMEBRIDGE_SERVICE" 2>/dev/null || true
        systemctl show "$HOMEBRIDGE_SERVICE" -p MainPID -p ActiveState -p SubState 2>/dev/null || true
        pid=$(systemctl show "$HOMEBRIDGE_SERVICE" -p MainPID --value 2>/dev/null || printf '0')
        [ "$pid" = "0" ] || ps -o pid,ppid,stat,%cpu,%mem,etime,comm -p "$pid" 2>/dev/null || true

        printf '\n-- relevant recent logs --\n'
        tail -n 240 "$SYSLOG" 2>/dev/null |
            grep -E 'homebridge|dhcpcd|lan78xx|homebridge-network-watchdog' || true
        dmesg 2>/dev/null |
            grep -Ei 'under.voltage|thrott|lan78xx|watchdog|oom|I/O error|ext4|mmc' |
            tail -n 120 || true
        printf '===== end watchdog trace: %s =====\n' "$label"
    } >> "$TRACE_LOG" 2>&1 || log "could not append trace '$label'"

    sync || true
}

clear_network_state() {
    rm -f "$NETWORK_REBOOT_MARKER" "$NETWORK_RETRY_MARKER"
}

clear_homebridge_state() {
    rm -f "$HOMEBRIDGE_RESTART_MARKER" "$HOMEBRIDGE_REBOOT_MARKER"
}

retry_due() {
    interval=$1
    now=$(date +%s)
    last=$(read_epoch "$NETWORK_RETRY_MARKER")
    [ $((now - last)) -ge "$interval" ]
}

mark_network_retry() {
    date +%s > "$NETWORK_RETRY_MARKER"
}

reset_network() {
    label=$1
    mark_network_retry
    trace_snapshot "$label-before-network-reset"
    log "network is unhealthy ($(network_fault_reason)); resetting $IFACE and $NETWORK_SERVICE"

    systemctl stop "$NETWORK_SERVICE" || true
    ip link set dev "$IFACE" down || true
    sleep 2
    ip link set dev "$IFACE" up || true
    systemctl start "$NETWORK_SERVICE" || true

    attempt=0
    while [ "$attempt" -lt "$RESET_WAIT_ATTEMPTS" ]; do
        sleep "$RESET_WAIT_SECONDS"
        if [ "$(network_fault_reason)" = "healthy" ]; then
            log "network recovered after interface reset"
            trace_snapshot "$label-network-reset-recovered"
            return 0
        fi
        attempt=$((attempt + 1))
    done

    log "network is still unhealthy after interface reset ($(network_fault_reason))"
    trace_snapshot "$label-network-reset-failed"
    return 1
}

request_one_reboot() {
    marker=$1
    reason=$2
    label=$3
    {
        date +%s
        current_boot_id
        printf '%s\n' "$reason"
    } > "$marker"

    trace_snapshot "$label"
    log "$reason; requesting one system reboot"
    sync || true

    if ! systemctl reboot; then
        log "system reboot request failed"
        rm -f "$marker"
        return 1
    fi
}

handle_network_failure() {
    reason=$(network_fault_reason)

    if router_maintenance_window; then
        log "network unhealthy during scheduled router maintenance ($reason); deferring recovery"
        return 0
    fi

    if [ -f "$NETWORK_REBOOT_MARKER" ]; then
        marker_boot_id=$(sed -n '2p' "$NETWORK_REBOOT_MARKER" 2>/dev/null || true)
        if [ "$marker_boot_id" = "$(current_boot_id)" ]; then
            log "network remains unhealthy after a reboot request; suppressing reboot loop"
            return 0
        fi

        if retry_due "$POST_REBOOT_RETRY_SECONDS"; then
            log "network remains unhealthy after watchdog reboot; trying a rate-limited interface reset"
            reset_network "post-reboot-network-retry" && clear_network_state
        fi
        return 0
    fi

    if reset_network "initial-network-failure"; then
        clear_network_state
        return 0
    fi

    request_one_reboot "$NETWORK_REBOOT_MARKER" "network did not recover after interface reset" "before-network-watchdog-reboot"
}

handle_homebridge_failure() {
    reason=$(homebridge_fault_reason)
    now=$(date +%s)

    if [ -f "$HOMEBRIDGE_REBOOT_MARKER" ]; then
        marker_boot_id=$(sed -n '2p' "$HOMEBRIDGE_REBOOT_MARKER" 2>/dev/null || true)
        if [ "$marker_boot_id" = "$(current_boot_id)" ]; then
            log "homebridge remains unhealthy after a reboot request; suppressing reboot loop"
            return 0
        fi
        log "homebridge remains unhealthy after watchdog reboot; suppressing additional reboots"
        return 0
    fi

    if [ -f "$HOMEBRIDGE_RESTART_MARKER" ]; then
        restarted=$(read_epoch "$HOMEBRIDGE_RESTART_MARKER")
        if [ $((now - restarted)) -lt "$HOMEBRIDGE_RESTART_WAIT" ]; then
            log "homebridge is still recovering ($reason); waiting before escalation"
            return 0
        fi

        request_one_reboot "$HOMEBRIDGE_REBOOT_MARKER" "homebridge remained unhealthy after service restart ($reason)" "before-homebridge-watchdog-reboot"
        return 0
    fi

    trace_snapshot "before-homebridge-service-restart"
    log "homebridge is unhealthy ($reason); restarting $HOMEBRIDGE_SERVICE"
    date +%s > "$HOMEBRIDGE_RESTART_MARKER"
    systemctl restart "$HOMEBRIDGE_SERVICE" || log "homebridge restart command failed"
}

mkdir -p "$STATE_DIR"

if [ "${1:-}" = "--check-only" ]; then
    network_reason=$(network_fault_reason)
    homebridge_reason=$(homebridge_fault_reason)
    printf 'network=%s homebridge=%s\n' "$network_reason" "$homebridge_reason"
    [ "$network_reason" = "healthy" ] && [ "$homebridge_reason" = "healthy" ]
    exit
fi

if [ "$(network_fault_reason)" != "healthy" ]; then
    handle_network_failure
    exit 0
fi

clear_network_state

if [ "$(homebridge_fault_reason)" != "healthy" ]; then
    handle_homebridge_failure
    exit 0
fi

clear_homebridge_state
exit 0
