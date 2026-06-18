#!/usr/bin/env bash
set -eu

REPO_ROOT="${REPO_ROOT:-/home/pi/git/respi}"
ASUS_USER="${ASUS_USER:-biogerm}"
ASUS_HOST="${ASUS_HOST:-192.168.0.25}"
PI_SOURCE_IP="${PI_SOURCE_IP:-192.168.0.180}"
RELAY_PORT="${RELAY_PORT:-54322}"
REMOTE_BIN="${REMOTE_BIN:-/tmp/asus_udp_relay_nolibc}"
REMOTE_LOG="${REMOTE_LOG:-/dev/null}"
SRC="${SRC:-$REPO_ROOT/homebridge-roborock/relay/tools/asus_udp_relay_nolibc.c}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/roborock-relay}"
LOCAL_BIN="${LOCAL_BIN:-$CACHE_DIR/asus_udp_relay_nolibc}"
LOCAL_REBUILT=0

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=no
)

log() {
  printf '%s %s\n' "$(date -Is)" "$*"
}

asus() {
  ssh "${SSH_OPTS[@]}" "$ASUS_USER@$ASUS_HOST" "$@"
}

build_local_binary() {
  if [ ! -x "$LOCAL_BIN" ] || [ "$SRC" -nt "$LOCAL_BIN" ]; then
    mkdir -p "$CACHE_DIR"
    log "building relay binary: $LOCAL_BIN"
    gcc -Os -fno-builtin -fno-stack-protector -nostdlib -static \
      -Wl,--build-id=none \
      -o "$LOCAL_BIN" "$SRC"
    chmod 0755 "$LOCAL_BIN"
    LOCAL_REBUILT=1
  fi
}

ensure_remote_binary() {
  if [ "$LOCAL_REBUILT" -eq 1 ] || ! asus "test -x '$REMOTE_BIN'"; then
    log "deploying relay binary to ASUS: $REMOTE_BIN"
    scp "${SSH_OPTS[@]}" "$LOCAL_BIN" "$ASUS_USER@$ASUS_HOST:$REMOTE_BIN"
    asus "chmod 0755 '$REMOTE_BIN'"
  fi
}

ensure_firewall_rule() {
  asus "/usr/sbin/iptables -C INPUT -p udp -s '$PI_SOURCE_IP' --dport '$RELAY_PORT' -j ACCEPT 2>/dev/null || /usr/sbin/iptables -I INPUT 1 -p udp -s '$PI_SOURCE_IP' --dport '$RELAY_PORT' -j ACCEPT"
}

ensure_relay_running() {
  if asus "ps | grep '[a]sus_udp_relay_nolibc' >/dev/null"; then
    return 0
  fi

  log "starting ASUS relay"
  asus "'$REMOTE_BIN' >'$REMOTE_LOG' 2>&1 < /dev/null &"
  sleep 1
  asus "ps | grep '[a]sus_udp_relay_nolibc' >/dev/null"
}

main() {
  build_local_binary
  ensure_remote_binary
  ensure_firewall_rule
  ensure_relay_running
  log "relay healthy"
}

main "$@"
