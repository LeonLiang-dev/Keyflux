# Air75 V3 ANSI: read-only discovery

The user approved phase 1 on 2026-11-02: identify the connected Air75 V3 ANSI,
read its firmware, active profile, LED count and lighting configuration. Later
lighting control and desktop integration are outside this change.

## Target and sources

- macOS Apple Silicon, wired USB, VID/PID `19f5:1028`, interface 3,
  usage page 1 / usage 0, 64-byte input and output reports without report IDs.
- User's NuPhy IO screenshot: firmware `1.0.23.6`, client `2.2.8`.
- Official client: <https://drive.nuphy.io/static/js/main.eff2c3e9.js>, SHA-256
  `b247cc2093d77cf5d5f6fb7c76c8d7d2f4792e525f5ccc797a8b60274f95c6ac`;
  its device table matches PID 4136 to Air75V3.
- Existing MIT protocol reference:
  <https://github.com/NuPhyLab/Air75-V3-RGB-Lab/blob/9bd300bc6f7eaaad8f766a1a6ef752bbf530088d/native/HIDBridge.swift>.
  This reference documents 22-byte D5 state for 1.0.23.6 and a one-byte D1
  count of 104. These are expectations until verified on the attached keyboard.

## Design

Add `keyflux hardware-probe-air75` as an explicit one-shot read-only command.
The command rejects positional arguments and runtime options before device access.
It does not initialize the runtime state directory or read/write recovery records.

A separate native transport opens only the matching Air75 USB control interface,
non-exclusively, and rejects missing or multiple matches. Both Zig framing and
the native transport restrict queries to A1 (8 bytes, firmware), A0 (8 bytes,
geometry/profile), D1 (1 byte, count), D5 (22 bytes, current profile).
No payload, nonzero offset, other opcode, or setter is accepted.

Reuse pure HID descriptor and S4 reply validation across the two devices;
keep the existing Kick75 transport, write gates and recovery format unchanged.
Derive the existing XOR key from A1 without setting/changing the device key.
Check response marker, checksum, command and plain/masked route. Pin phase 1 to
the user's firmware family/version and known geometry; re-read geometry and
firmware around the snapshot to reject a changing profile/session.

JSON reports model, USB identity, firmware version, non-session firmware bytes,
profile, non-session geometry bytes, LED count and all 22 raw state bytes.
It explicitly declares read-only operation and disabled lighting writes.
Do not export serials, USB paths, location IDs or the XOR key. The 22-byte
configuration is diagnostic evidence, not a claim of recoverable lighting.

Keep the model descriptor `recognized`, with no lighting, restore or per-key
capabilities. Leave the desktop catalog and preview-only layout unchanged.

## Implementation and validation checklist

1. Add shared pure response/descriptor validation; preserve Kick75 API aliases.
2. Add Air75 read-only codec, probe and strictly bounded native transport.
3. Add CLI, recognized model descriptor and English/Chinese usage documentation.
4. Test query boundaries, malformed replies/descriptors, wrong firmware/geometry,
   changing profiles/session, the one-byte count and retention of all state bytes.
5. Build and run core tests plus simulated integration/regression checks.
6. Run the explicit probe on the attached keyboard and record sanitized output
   and limits. A failed probe is reported as failed rather than enabling writes.

No third-party application source is executed. No lighting mutation, firmware
update, keymap operation, key setter, desktop connection, or automated AI-follow
operation is part of phase 1.
