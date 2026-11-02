# Air75 V3 ANSI: phase 1 read-only probe

This phase queries a wired USB Air75 V3 ANSI on macOS. It does not add the
keyboard to the desktop catalog, grant lighting writes, or establish that its
original lighting can be restored. The descriptor stays `recognized`, with
all lighting and recovery capabilities disabled.

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

Kick75's command, write gates, routing and journal stay separate. Air75's
keyboard layout stays `preview_only` and outside the desktop catalog.

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
