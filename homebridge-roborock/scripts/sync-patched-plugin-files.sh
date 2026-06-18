#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-/usr/lib/node_modules/homebridge-xiaomi-roborock-vacuum}"
REPO_ROOT="${REPO_ROOT:-/home/pi/git/respi}"
DEST="$REPO_ROOT/homebridge-roborock/plugin-files/homebridge-xiaomi-roborock-vacuum"

files=(
  "models/speedmodes.js"
  "models/models.js"
  "miio/lib/models.js"
  "index.js"
  "miio/lib/device_info.js"
  "miio/lib/devices/vacuum.js"
  "package.json"
)

if [ ! -d "$PLUGIN_ROOT" ]; then
  printf 'plugin root not found: %s\n' "$PLUGIN_ROOT" >&2
  exit 1
fi

mkdir -p "$DEST"

for file in "${files[@]}"; do
  src="$PLUGIN_ROOT/$file"
  dst="$DEST/$file"
  if [ ! -f "$src" ]; then
    printf 'missing expected file: %s\n' "$src" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
done

{
  printf 'synced_at=%s\n' "$(date -Is)"
  printf 'plugin_root=%s\n' "$PLUGIN_ROOT"
  if command -v node >/dev/null 2>&1; then
    node -e 'const p=require(process.argv[1]); console.log(`package=${p.name}@${p.version}`)' "$PLUGIN_ROOT/package.json" || true
  fi
} > "$DEST/.sync-info"

printf 'copied patched plugin files to %s\n' "$DEST"
git -C "$REPO_ROOT" status --short "$DEST"
