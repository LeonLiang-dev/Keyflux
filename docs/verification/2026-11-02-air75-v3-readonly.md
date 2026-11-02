# Air75 V3 ANSI read-only verification — 2026-11-02

## Scope and result

Phase 1 passed on the attached USB Air75 V3 ANSI, macOS / Apple Silicon,
firmware **1.0.23.6**, Mac profile. The new command is:

```sh
./zig-out/bin/keyflux hardware-probe-air75
```

The device returned firmware bytes `[23,0,1,170,6,0]`, geometry
`[0,8,4,6,16,130]`, profile `0`, LED count **104**, 64-byte input/output
reports and the full **22-byte** lighting state:

```json
[6,50,2,0,1,4,0,0,0,4,0,2,1,0,255,0,0,4,4,4,4,4]
```

The query sequence was A1 → A0 → D1 → D5 → A0 → A1. The two final queries
confirmed the firmware/key and profile/geometry had not changed during the
snapshot. The count and state length match the pinned protocol reference.
The output omits session/reserved identity bytes and USB identifiers that could
identify the individual device (serial, path, location). Standard VID/PID and
interface metadata remain public. See [sanitized raw evidence](../evidence/air75-v3-readonly-20261102.json).

HID output was used only to send read requests. The native command allowlist
contains no D6/D8 setters, EE key setter, firmware updater, keymap writer or
restore operation. No recovery journal was initialized or modified.

## Software verification

- `zig fmt --check build.zig src`: passed.
- `zig build test -j2`: passed, including existing Kick75 regression tests,
  new Air75 mock-query tests and the native C query-boundary test.
- `zig build -Doptimize=ReleaseSafe -j2`: passed on native macOS.
- Cross-compilation with `-Dtarget=x86_64-windows-gnu`: passed. The new
  Air75 probe returns `UnsupportedPlatform` there; Windows hardware was not tested.
- `python3 tests/integration.py zig-out/bin/keyflux`: **13 passed**. Invalid
  options are checked individually before HID access; model capabilities remain
  disabled. Simulated runtime/IPC behavior also passed.
- `python3 tests/workflow.py zig-out/bin/keyflux`: **3 passed**.
- `python3 scripts/check-vendor.py`: all **12** pinned HIDAPI files matched.
- `validate-model` for both Air75 and Kick75: passed.

Zig checks used `ZIG_GLOBAL_CACHE_DIR=/private/tmp/keyflux-zig-global` because
the default global cache is outside the workspace sandbox. HID open and local
IPC were also restricted inside the sandbox; authorized runs outside it passed.
This was an execution-environment restriction, not a bypass of hardware gates.

## Remaining work

The Air75 descriptor is still `recognized`; solid lighting, restore, per-key
and readback capability claims remain false. The existing preview stays
`preview_only`, and the desktop application still connects only supported
Kick75 devices. The 104 count does not establish a physical LED mapping.

Lighting writes, exact original-state recovery, RGB encoding, flash persistence,
physical unplug/replug, sleep/wake, wireless control and Windows hardware support
were not tested or enabled. The frontend and Rust shell were not modified, and
their full UI/manual hardware suites were not rerun for this CLI-only phase.
