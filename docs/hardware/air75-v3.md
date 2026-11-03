# Air75 V3 ANSI: read-only probe and experimental manual main lighting

The read-only probe and separate manual main-light commands target wired USB
Air75 V3 ANSI, firmware **1.0.23.6**, macOS / Mac profile. The descriptor is
`experimental`. Manual main-color readback and exact original-state restoration
passed. The desktop app offers explicit, short main-light tests. Air75 AI
following, side and per-key control are outside the current desktop scope.

## Usage

```sh
zig build -Doptimize=ReleaseSafe
./zig-out/bin/keyflux diagnose
./zig-out/bin/keyflux hardware-probe-air75
./zig-out/bin/keyflux validate-model models/nuphy-air75-v3.json
```

Use wired mode and close/disconnect other HID configurators such as NuPhy IO.
The command opens non-exclusively, rejects runtime flags and extra arguments,
and does not initialize runtime state or modify recovery records. An ephemeral
per-user lock coordinates Keyflux probes, not third-party clients.

## Desktop connection and color test

Start the app with `./scripts/dev-macos.sh` and click **连接键盘**. If both
supported models are present, select the device to connect. An Air75 session
shows the connected model and its ANSI layout. Editing and saving a palette
update the preview and theme. **测试主灯** applies the selected color at up to
15% brightness, holds it for three seconds and restores the saved configuration.
The core holds the device lock throughout this test.

If a compatible recovery capture exists, **恢复原灯效** is available instead.
The test retains the capture if the device disappears or its configuration
changes during the hold. Reconnect the original keyboard at the same USB port
to recover. Air75 connection is read-only until a test or recovery is requested.

## Query contract

Only USB `19f5:1028`, usage page 1 / usage 0, interface 3 is selected. The HID
descriptor must specify 64-byte input/output reports without report IDs.
Missing/multiple matches, unsupported descriptors, invalid replies and timeouts
fail without a setter, key change or blind query retry.

| Command | Length | Offset / profile | Query |
| --- | --- | --- | --- |
| A1 | 8 | 0 / 0 | Firmware; derive existing key without changing it |
| A0 | 8 | 0 / 0 | Geometry and active Mac/Win profile |
| D1 | 1 | 0 / 0 | LED count; padding is not a high byte |
| D5 | 22 | 0 / active | Raw lighting configuration |

The sequence A1 → A0 → D1 → D5 → A0 → A1 checks profile/geometry/session
stability. Every response validates marker, command, status, checksum and plain
or XOR-masked route. Both Zig and native layers restrict the command envelope;
the native layer also rejects nonzero payload/padding. Queries send HID output
reports to request data, but never configuration setters.

Phase 1 pins `1.0.23.6` (`[23,0,1,170,6,0]`), the expected Air75 geometry and
LED count 104. Unknown combinations stop rather than widening support. All 22
D5 bytes are preserved, including byte 21 which can exceed the setter's
documented range. This diagnostic snapshot is not a writable recovery capture.
The count does not establish physical key/LED mapping.

Output includes firmware version, six meaningful firmware/geometry bytes,
profile, LED count, USB/report shape and all lighting bytes. Session/reserved
trailing A1/A0 bytes, derived key, serial, USB path and location ID are omitted.
`read_only:true` and `main_write_enabled:false` are always present.

Each desktop session binds to the detected model and USB identity. The Air75
ANSI layout provides a screen preview. It contains no physical LED mapping.

## Manual main lighting and recovery

```sh
./zig-out/bin/keyflux hardware-status-air75
./zig-out/bin/keyflux hardware-solid-air75 '#00FFFF' 15
./zig-out/bin/keyflux hardware-restore-air75
# Opt-in three-color test with cleanup; watch the physical keyboard:
python3 scripts/test-air75-main-macos.py
```

The solid command keeps its color until explicit restoration. The manual test
shows red, cyan and purple at 15% brightness for three seconds each and restores
the initial state on completion or normal interruption. It refuses an older
recovery capture. Neither this script nor its physical test runs automatically
in CI. SIGKILL/power loss cannot run cleanup; the durable capture remains.

These commands use the canonical `~/Library/Application Support/Keyflux/air75-recovery.json`.
They reject `--state-dir`, simulation and OTLP flags. Optional `--expect-device`
binds mutations to the current 64-character hashed device/port identity reported
by status. Recovery requires the original device, USB port, firmware and profile.
The status command is read-only with respect to keyboard configuration.

The read-only transport entry remains restricted to its original four queries.
A separate native entry accepts only D6 length **9**, offset **0**, profile **0**,
with bounded stock-effect fields. Bytes 9–21 never enter a setter. Before each
mutation, a pending record is atomically saved and fsynced. It retains the first
original capture across colors. Unknown firmware, invalid/mismatched journals,
off/custom/preset originals, unencodable RGB, concurrent edits and changed
unowned fields block writes. Pending recovery blocks another color.

Configuration writes are separated by at least one second. D6 must echo the
payload; bounded D5 reads settle afterwards without repeating an uncertain
setter. Solid readback accepts only exact requested RGB or its known byte-HSV
projection, with every other byte exact. Restoration requires the entire saved
22-byte state. A second payload with inverse RGB encoding is allowed only after
a successful direct restore ACK and exactly the known HSV projection. Failures
attempt separate original recovery where safe and retain the record if recovery
cannot be verified. The record is removed only after exact restoration.

Current probe fields `read_only:true` / `main_write_enabled:false` describe that
one-shot **query operation**; `hardware-status-air75` separately reports manual
control availability. They do not enable any desktop follower.

The [phase 2 record](../verification/2026-11-02-air75-v3-main.md) separates real
configuration readback from optical observation. Flash persistence, sustained
write frequency, custom palettes, physical unplug/sleep recovery and Windows
hardware are unverified. Main-light restoration preserves the saved effect
configuration, not the animation's elapsed phase.

## Sources and verification

- User screenshots: Air75 V3 ANSI `1.0.23.6`, NuPhy IO `2.2.8`.
- [Official NuPhy IO client](https://drive.nuphy.io/static/js/main.eff2c3e9.js),
  SHA-256 `b247cc2093d77cf5d5f6fb7c76c8d7d2f4792e525f5ccc797a8b60274f95c6ac`:
  device table binds PID 4136 to Air75V3.
- [Pinned MIT Air75 reference](https://github.com/NuPhyLab/Air75-V3-RGB-Lab/blob/9bd300bc6f7eaaad8f766a1a6ef752bbf530088d/native/HIDBridge.swift),
  source SHA-256 `97cf8c895b3a4aa95af917ba6943b2eb58d6dd33fcf779e63c9af81d8d1bdd2c`:
  version layout, one-byte D1, 22-byte D5 and reply routing.

See the [phase 1 design](../superpowers/specs/2026-11-02-air75-v3-readonly-design.md).
Software results and sanitized hardware evidence are recorded in the
[phase 1 verification](../verification/2026-11-02-air75-v3-readonly.md) and
[device snapshot](../evidence/air75-v3-readonly-20261102.json). They do not certify lighting writes,
restoration, flash persistence, wireless or Windows hardware support.
