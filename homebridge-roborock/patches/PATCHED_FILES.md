# Patched Homebridge Plugin Files

Live patched plugin path on Pi:

```text
/usr/lib/node_modules/homebridge-xiaomi-roborock-vacuum
```

Plugin version observed during troubleshooting:

```text
homebridge-xiaomi-roborock-vacuum@0.20.1
```

The live files still need to be copied from the Pi when back on the home
network. Use:

```sh
homebridge-roborock/scripts/sync-patched-plugin-files.sh
```

## Final Intended Patch Set

These files were patched and should be captured from the live Pi install:

- `models/speedmodes.js`
  - Added a `gen5` speed mode table.
  - Values:
    - Off: `-1`
    - Quiet: `101`
    - Balanced: `102`
    - Turbo: `103`
    - Max: `104`
    - Max+: `108`
    - Custom: `106`

- `models/models.js`
  - Added or adjusted `roborock.vacuum.a23`.
  - Uses `speedmodes["gen5"]`.
  - Uses `watermodes["gen1+custom"]`.

- `miio/lib/models.js`
  - Added model mapping:

```js
"roborock.vacuum.a23": Vacuum,
```

- `index.js`
  - Passes the configured model into `miio.device(...)`.
  - Passes the configured port into `miio.device(...)`.
  - Purpose: prevent the bundled miio library from blocking A23 on model
    discovery, and allow BB8 to use the ASUS relay on `54322`.

- `miio/lib/device_info.js`
  - `enrich()` returns early when both configured model and token are already
    available.
  - Purpose: avoid blocking new Roborock models on `miIO.info`.

- `miio/lib/devices/vacuum.js`
  - Makes `get_consumable` optional/tolerant.
  - Status still uses `get_status`.

## Homebridge Config

BB8 now uses the ASUS relay port:

```json
"ip": "192.168.0.25",
"port": 54322,
"model": "roborock.vacuum.a23"
```

## Temporary Patches That Were Reverted

These files may have backup files on Pi, but their temporary diagnostics should
not be treated as final plugin changes:

- `miio/lib/packet.js`
  - Temporary miIO packet diagnostics were reverted.

- `miio/lib/devices/vacuum.js`
  - Temporary MIoT `get_properties` fallback was reverted.
  - The final kept change is only the `get_consumable` tolerance above.

- `miio/lib/device_info.js`
  - Temporary method diagnostics were reverted.
  - The final kept change is the configured model/token early return above.

## Backup Files Seen On Pi

The Pi install may contain backup files created during the patching session:

- `models/speedmodes.js.codex-before-gen5`
- `models/models.js.codex-before-gen5`
- `miio/lib/device_info.js.codex-before-miio-method-diag`
- `miio/lib/devices/vacuum.js.codex-before-a23-miot-fallback`
- `miio/lib/packet.js.codex-before-miio-diag`

Do not restore these blindly. Compare them with the live files first.
