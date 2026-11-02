# Air75 V3 phase 2: manual main lighting and exact recovery

User authorization: following successful phase 1, the user asked to execute
phase 2 (main lighting, readback and original-state recovery). Desktop/AI
integration, per-key palettes, wireless and side setters remain outside scope.

Continue on `feat/air75-v3`. Preserve the original read-only command and gate.
Add separate manual solid/status/restore commands. Native transport permits
only D6 length 9, offset 0, Mac profile through a distinct write entry. Never
broaden the read entry, allow D8/EE/keymap/firmware commands, or change a palette.

Pin to ANSI USB 19f5:1028, firmware 1.0.23.6, known geometry, 104 LEDs, 64-byte
reports and Mac profile. Bind recovery to a hashed local device/port identity,
firmware and profile. Use the existing per-user Air75 lock across probing,
atomic/fsynced `air75-recovery.json` updates and hardware operations.

Before the first write capture all 22 configuration bytes. Require a supported
stock main effect and exactly encodable saved RGB; reject off/custom/preset
states that cannot be restored by the narrow 9-byte setter. Preserve bytes
9–21 exactly, including fields not writable through this phase. Write a pending
intent before any setter. A pending record blocks another solid; explicit
restoration is allowed only on the original identity/profile/firmware with
unchanged unowned fields. Never replace an older original capture.

Use the existing MIT byte-HSV arithmetic, now tested against the pinned Air75
firmware. Predict requested RGB readback; accept only exact predicted/direct
RGB and identical remaining fields. Restoration must equal the entire original
22-byte snapshot. A second encoding is allowed only after a successful ACK and
the exact known HSV projection of a directly sent saved RGB. No ambiguous
write retry, tolerance comparison or side-field normalization is allowed.

Delay configuration mutations at least one second; after a write allow bounded
read-only settling checks. Timeouts, ACK mismatch and unknown readbacks attempt
one separate original recovery; retain the journal on any unverified result.
No-op commands do not write. Remove the journal only after exact recovery.

Validate with codec/native boundary tests, mock write/readback/recovery and
failure cases, journal serialization, and existing simulation regressions.
Then run an explicitly manual low-brightness red/cyan/purple test with cleanup
on normal exit/signals, independent readback, original-state verification and
sanitized evidence. Do not claim optical appearance, flash persistence,
sleep/wake or physical hotplug coverage from configuration readback.

Protocol sources and MIT attribution are the same pinned sources as phase 1;
the existing native color module and durable file API are reused. Record
software tests separately from observed hardware results.
