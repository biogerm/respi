#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root." >&2
    exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_file="$script_dir/systemd/20-pi-hardware-watchdog.conf"
target_dir="/etc/systemd/system.conf.d"
target_file="$target_dir/20-pi-hardware-watchdog.conf"

if [ ! -r "$source_file" ]; then
    echo "Missing hardware watchdog configuration: $source_file" >&2
    exit 1
fi

if [ ! -c /dev/watchdog ]; then
    echo "No /dev/watchdog device is available; hardware watchdog was not configured."
    exit 0
fi

install -d -m 0755 "$target_dir"
install -m 0644 "$source_file" "$target_file"

# system.conf changes require the manager process to re-exec.
systemctl daemon-reexec

systemctl show \
    -p RuntimeWatchdogUSec \
