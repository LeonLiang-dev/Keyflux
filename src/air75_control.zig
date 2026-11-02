//! Manual main-only Air75 control. Recovery ownership is separate from Kick75.
const std = @import("std");
const air = @import("air75.zig");
const p = @import("platform.zig");
const s4 = @import("nuphy_s4.zig");
const protocol = @import("protocol.zig");
const colors = @import("nuphy_color.zig");
const devices = @import("device.zig");
pub const State = [22]u8;

pub fn writable(info: air.Probe) !void {
    if (!std.mem.eql(u8, info.model_id, "nuphy-air75-v3") or
        !std.mem.eql(u8, &info.firmware, &.{ 23, 0, 1, 170, 6, 0 }) or
        info.led_count != 104 or info.usb.vendor_id != 0x19f5 or info.usb.product_id != 0x1028 or
        info.usb.input_bytes != 64 or info.usb.output_bytes != 64 or info.state_bytes != 22 or
        info.usb.interface_number != 3 or info.usb.usage_page != 1 or info.usb.usage != 0) return error.UnverifiedAir75Firmware;
    var geometry: [8]u8 = @splat(0);
    geometry[0..6].* = info.geometry;
    try air.validateGeometry(geometry);
    if (info.profile != 0 or info.geometry[0] != 0) return error.UnverifiedProfile;
}
fn validMain(state: State) !void {
    // Custom/off/preset modes require broader ownership than the narrow setter.
    if (state[0] < 1 or state[0] > 20 or state[1] > 100 or state[2] > 4 or
        state[3] > 3 or state[4] > 1 or state[5] > 7) return error.UnsupportedOriginalEffect;
}
pub fn recoverable(state: State) !void {
    try validMain(state);
    _ = try colors.encodeExact(state[6..9].*);
}
pub fn solidState(original: State, light: devices.Lighting) !State {
    if (light.brightness > 100) return error.InvalidBrightness;
    try recoverable(original);
    var result = original;
    result[0] = 3;
    result[1] = light.brightness;
    result[4] = 0;
    result[6..9].* = colors.readback(.{ light.color.r, light.color.g, light.color.b });
    return result;
}
pub fn writeFrame(payload: [9]u8, key: u8) !protocol.Report {
    var state: State = @splat(0);
    state[0..9].* = payload;
    try validMain(state);
    var request: protocol.Report = @splat(0);
    request[0] = 0x55;
    request[1] = 0xd6;
    request[4..8].* = .{ 9 ^ key, key, key, key };
    for (payload, 0..) |byte, i| request[8 + i] = byte ^ key;
    request[3] = protocol.checksum(request);
    return request;
}
pub const Journal = struct {
    schema_version: u8 = 1,
    format: []const u8 = "air75-v3-1.0.23.6-main-v1",
    fingerprint: [64]u8,
    original: air.Probe,
    expected: State,
    pending: bool = false,
    pub fn validate(self: Journal, current: air.Probe, identity: [64]u8) !void {
        if (self.schema_version != 1 or !std.mem.eql(u8, self.format, "air75-v3-1.0.23.6-main-v1")) return error.InvalidRecoveryRecord;
        try writable(self.original);
        try writable(current);
        for (self.fingerprint) |c| if (!std.ascii.isHex(c)) return error.InvalidRecoveryRecord;
        if (!std.mem.eql(u8, &self.fingerprint, &identity) or
            !std.mem.eql(u8, &self.original.firmware, &current.firmware) or
            !std.mem.eql(u8, &self.original.geometry, &current.geometry)) return error.RecoveryIdentityMismatch;
        try recoverable(self.original.state);
        try validMain(self.expected);
        if (!std.mem.eql(u8, self.original.state[9..], self.expected[9..])) return error.InvalidRecoveryRecord;
        if (!std.mem.eql(u8, self.original.state[9..], current.state[9..])) return error.UnownedLightingChanged;
    }
    pub fn guardSolid(self: Journal, current: air.Probe, identity: [64]u8) !void {
        try self.validate(current, identity);
        if (self.pending) return error.RecoveryRequired;
        if (!std.mem.eql(u8, &self.expected, &current.state)) return error.ConcurrentDeviceChange;
    }
};

pub fn matches(expected: State, wire: [9]u8, observed: State) bool {
    if (std.mem.eql(u8, &expected, &observed)) return true;
    return std.mem.eql(u8, &wire, observed[0..9]) and std.mem.eql(u8, expected[9..], observed[9..]);
}
fn writeOnce(device: anytype, before: State, wire: [9]u8) !State {
    try writable(device.info);
    if (!std.mem.eql(u8, &before, &(try device.readState()))) return error.ConcurrentDeviceChange;
    device.delay(1000);
    if (!std.mem.eql(u8, &before, &(try device.readState()))) return error.ConcurrentDeviceChange;
    try device.writeData(wire); // Exactly one setter. Only read-only settling follows.
    device.delay(150);
    return device.readState();
}
pub fn setSolid(device: anytype, light: devices.Lighting) !State {
    const before = device.info.state;
    const target = try solidState(before, light);
    var wire = target[0..9].*;
    wire[6..9].* = .{ light.color.r, light.color.g, light.color.b };
    var observed = try writeOnce(device, before, wire);
    for (0..5) |attempt| {
        if (!std.mem.eql(u8, before[9..], observed[9..])) return error.UnownedLightingChanged;
        if (matches(target, wire, observed)) return observed;
        if (attempt < 4) {
            device.delay(120);
            observed = try device.readState();
        }
    }
    return error.ReadbackMismatch;
}
pub fn restoreExact(device: anytype, target: State) !State {
    try recoverable(target);
    const before = try device.readState();
    if (!std.mem.eql(u8, target[9..], before[9..])) return error.UnownedLightingChanged;
    if (std.mem.eql(u8, &target, &before)) return before;
    var wire = target[0..9].*;
    var observed = try writeOnce(device, before, wire);
    for (0..5) |attempt| {
        if (!std.mem.eql(u8, target[9..], observed[9..])) return error.UnownedLightingChanged;
        if (std.mem.eql(u8, &target, &observed)) return observed;
        if (attempt < 4) {
            device.delay(120);
            observed = try device.readState();
        }
    }
    var projected = target;
    projected[6..9].* = colors.readback(target[6..9].*);
    if (!std.mem.eql(u8, &projected, &observed)) return error.ReadbackMismatch;
    wire[6..9].* = try colors.encodeExact(target[6..9].*);
    if (std.mem.eql(u8, &wire, target[0..9])) return error.ReadbackMismatch;
    observed = try writeOnce(device, observed, wire);
    for (0..5) |attempt| {
        if (!std.mem.eql(u8, target[9..], observed[9..])) return error.UnownedLightingChanged;
        if (std.mem.eql(u8, &target, &observed)) return observed;
        if (attempt < 4) {
            device.delay(120);
            observed = try device.readState();
        }
    }
    return error.ReadbackMismatch;
}

pub const Keyboard = struct {
    native: air.Native = .{},
    info: air.Probe = undefined,
    fingerprint: [64]u8 = undefined,
    pub fn connect(self: *Keyboard) !void {
        try air.open();
        errdefer p.kf_air75_close();
        self.info = try air.inspect(&self.native);
        try writable(self.info);
        var raw: [1024]u8 = undefined;
        const n = p.kf_air75_identity(&raw, raw.len);
        if (n < 4) return error.MissingDeviceIdentity;
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(raw[0..@intCast(n)], &hash, .{});
        self.fingerprint = std.fmt.bytesToHex(hash, .lower);
    }
    pub fn close(_: *Keyboard) void {
        p.kf_air75_close();
    }
    pub fn readState(self: *Keyboard) !State {
        const latest = try air.inspect(&self.native);
        try writable(latest);
        if (!std.mem.eql(u8, &self.info.geometry, &latest.geometry)) return error.ProfileChanged;
        return latest.state;
    }
    pub fn writeData(self: *Keyboard, payload: [9]u8) !void {
        const reply = try self.native.write(try writeFrame(payload, self.native.key), self.native.key);
        const echo = try s4.decode(reply, 0xd6, 9, 0, 0, self.native.key);
        if (!std.mem.eql(u8, &payload, echo[0..9])) return error.StateAckMismatch;
    }
    pub fn delay(_: *Keyboard, ms: u32) void {
        p.kf_sleep_ms(ms);
    }
};

pub const Result = struct {
    ok: bool = true,
    changed: bool = false,
    restored: bool = false,
    recovery_pending: bool = false,
    configuration_readback: bool = true,
    visual_verification: []const u8 = "required",
    unowned_fields_preserved: bool = true,
    color_quantized: bool = false,
    state: State,
};

/// Storage saves are durable before a setter; an older original is never replaced.
pub fn execute(device: anytype, storage: anytype, light: ?devices.Lighting) !Result {
    try writable(device.info);
    const saved = try storage.load();
    if (saved == null and light == null) return .{ .state = device.info.state };
    var journal = saved orelse Journal{ .fingerprint = device.fingerprint, .original = device.info, .expected = device.info.state };
    try journal.validate(device.info, device.fingerprint);
    if (light) |value| {
        try journal.guardSolid(device.info, device.fingerprint);
        const target = try solidState(device.info.state, value);
        var wire = target[0..9].*;
        wire[6..9].* = .{ value.color.r, value.color.g, value.color.b };
        if (matches(target, wire, device.info.state)) return .{ .state = device.info.state, .recovery_pending = saved != null };
        journal.expected = target;
        journal.pending = true;
        try storage.save(journal);
        const after = setSolid(device, value) catch |err| {
            // Concurrent/unowned changes must not be overwritten by rollback.
            if (err == error.ConcurrentDeviceChange or err == error.UnownedLightingChanged or err == error.ProfileChanged) return err;
            _ = restoreExact(device, journal.original.state) catch return error.RecoveryRequired;
            try storage.remove();
            return err;
        };
        journal.expected = after;
        journal.pending = false;
        try storage.save(journal);
        return .{ .changed = true, .state = after, .recovery_pending = true, .color_quantized = !std.mem.eql(u8, wire[6..9], after[6..9]) };
    }
    journal.pending = true;
    try storage.save(journal);
    const after = try restoreExact(device, journal.original.state);
    try storage.remove();
    return .{ .restored = true, .state = after };
}
