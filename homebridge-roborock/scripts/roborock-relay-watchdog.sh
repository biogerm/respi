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
STATE_FILE="${STATE_FILE:-$CACHE_DIR/watchdog.state}"
LOCK_FILE="${LOCK_FILE:-$CACHE_DIR/watchdog.lock}"
SUMMARY_EVERY_SECONDS="${SUMMARY_EVERY_SECONDS:-3600}"
LOCAL_REBUILT=0

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=no
)

log() {
  printf '%s %s\n' "$(date -Is)" "$*"
}

log_state() {
  local status="$1"
  shift
  local message="$*"
  local now old_status old_time

  mkdir -p "$CACHE_DIR"
  now="$(date +%s)"
  old_status=""
  old_time="0"

  if [ -r "$STATE_FILE" ]; then
    read -r old_status old_time < "$STATE_FILE" || true
    old_time="${old_time:-0}"
  fi

  if [ "$status" != "$old_status" ] || [ $((now - old_time)) -ge "$SUMMARY_EVERY_SECONDS" ]; then
    log "$message"
    printf '%s %s\n' "$status" "$now" > "$STATE_FILE"
  fi
}

lock_once() {
  mkdir -p "$CACHE_DIR"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
      log_state "already-running" "relay watchdog skipped: previous run still active"
      exit 0
    fi
  fi
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

deploy_remote_binary() {
  log_state "deploying" "deploying relay binary to ASUS: $REMOTE_BIN"
  if ! scp "${SSH_OPTS[@]}" "$LOCAL_BIN" "$ASUS_USER@$ASUS_HOST:$REMOTE_BIN"; then
    log_state "deploy-failed" "relay binary deployment failed: ASUS unreachable or scp failed"
    return 1
  fi
  if ! asus "chmod 0755 '$REMOTE_BIN'"; then
    log_state "deploy-failed" "relay binary deployment failed: chmod on ASUS failed"
    return 1
  fi
}

ensure_remote_state() {
  asus "
    [ -x '$REMOTE_BIN' ] || exit 20
    /usr/sbin/iptables -C INPUT -p udp -s '$PI_SOURCE_IP' --dport '$RELAY_PORT' -j ACCEPT 2>/dev/null || /usr/sbin/iptables -I INPUT 1 -p udp -s '$PI_SOURCE_IP' --dport '$RELAY_PORT' -j ACCEPT
    if ! ps | grep '[a]sus_udp_relay_nolibc' >/dev/null; then
      '$REMOTE_BIN' >'$REMOTE_LOG' 2>&1 < /dev/null &
      sleep 1
    fi
    ps | grep '[a]sus_udp_relay_nolibc' >/dev/null
  "
}

main() {
  lock_once
  build_local_binary

  if [ "$LOCAL_REBUILT" -eq 1 ]; then
    deploy_remote_binary || exit 0
  fi

  set +e
  ensure_remote_state
  rc=$?
  set -e

  if [ "$rc" -eq 20 ]; then
    deploy_remote_binary || exit 0
    set +e
    ensure_remote_state
    rc=$?
    set -e
  fi

  if [ "$rc" -eq 0 ]; then
    log_state "healthy" "relay healthy"
  elif [ "$rc" -eq 255 ]; then
    log_state "asus-unreachable" "relay check skipped: ASUS unreachable"
  else
    log_state "relay-failed" "relay check failed with status $rc"
  fi
}

main "$@"
