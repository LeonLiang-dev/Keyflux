const std = @import("std");
const air = @import("air75.zig");
const ctl = @import("air75_control.zig");
const colors = @import("nuphy_color.zig");
const protocol = @import("protocol.zig");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const eql = std.testing.expectEqualSlices;

fn fixture() air.Probe {
    return .{ .firmware = .{ 23, 0, 1, 170, 6, 0 }, .geometry = .{ 0, 8, 4, 6, 16, 130 }, .profile = 0, .profile_name = "mac", .led_count = 104, .state = .{ 6, 50, 2, 0, 1, 4, 0, 0, 0, 4, 0, 2, 1, 0, 255, 0, 0, 4, 4, 4, 4, 94 } };
}
const Storage = struct {
    journal: ?ctl.Journal = null,
    saves: usize = 0,
    fail_save: usize = 0,
    pub fn load(self: *Storage) !?ctl.Journal {
        return self.journal;
    }
    pub fn save(self: *Storage, journal: ctl.Journal) !void {
        self.saves += 1;
        if (self.fail_save == self.saves) return error.StateWriteFailed;
        self.journal = journal;
    }
    pub fn remove(self: *Storage) !void {
        self.journal = null;
    }
};
const Device = struct {
    info: air.Probe = fixture(),
    fingerprint: [64]u8 = @splat('a'),
    state: ctl.State = fixture().state,
    storage: ?*Storage = null,
    writes: usize = 0,
    reads: usize = 0,
    delay_ms: u32 = 0,
    direct: bool = false,
    disconnect: bool = false,
    ack_lost_once: bool = false,
    mismatch_once: bool = false,
    change_unowned: bool = false,
    concurrent: bool = false,
    pub fn readState(self: *Device) !ctl.State {
        self.reads += 1;
        if (self.disconnect) return error.DeviceDisconnected;
        if (self.concurrent and self.reads == 2) self.state[1] += 1;
        return self.state;
    }
    pub fn writeData(self: *Device, payload: [9]u8) !void {
        if (self.storage) |store| try expect(store.journal != null and store.journal.?.pending);
        self.writes += 1;
        self.state[0..9].* = payload;
        if (!self.direct) self.state[6..9].* = colors.readback(payload[6..9].*);
        if (self.change_unowned) self.state[21] ^= 1;
        if (self.mismatch_once and self.writes == 1) self.state[1] += 1;
        if (self.ack_lost_once and self.writes == 1) return error.HidTimeout;
    }
    pub fn delay(self: *Device, ms: u32) void {
        self.delay_ms += ms;
    }
};
const cyan = @import("device.zig").Lighting{ .color = .{ .r = 0, .g = 255, .b = 255 }, .brightness = 15 };

test "Air75 durable transaction captures once and restores all 22 original bytes" {
    var store: Storage = .{};
    var device: Device = .{ .storage = &store };
    const result = try ctl.execute(&device, &store, cyan);
    try expect(result.changed and result.recovery_pending);
    try expect(store.journal != null and !store.journal.?.pending);
    try eql(u8, &fixture().state, &store.journal.?.original.state);
    try eql(u8, fixture().state[9..], result.state[9..]);
    try expect(device.writes == 1 and device.delay_ms >= 1150);
    device.info.state = device.state;
    const duplicate = try ctl.execute(&device, &store, cyan);
    try expect(!duplicate.changed and device.writes == 1);
    const restored = try ctl.execute(&device, &store, null);
    try expect(restored.restored and !restored.recovery_pending);
    try eql(u8, &fixture().state, &device.state);
    try expect(store.journal == null and device.writes == 2);
}
test "Air75 failed durable save blocks setter and lost acknowledgement blocks new color" {
    var store: Storage = .{ .fail_save = 1 };
    var device: Device = .{ .storage = &store };
    try expectError(error.StateWriteFailed, ctl.execute(&device, &store, cyan));
    try expect(device.writes == 0);
    store = .{ .fail_save = 2 };
    try expectError(error.StateWriteFailed, ctl.execute(&device, &store, cyan));
    try expect(store.journal.?.pending and device.writes == 1);
    device.info.state = device.state;
    try expectError(error.RecoveryRequired, ctl.execute(&device, &store, cyan));
    try expect(device.writes == 1);
    _ = try ctl.execute(&device, &store, null);
    try expect(store.journal == null);
}
test "Air75 ambiguous and mismatched writes recover separately without repeating the color" {
    inline for ([_]bool{ false, true }) |timeout| {
        var store: Storage = .{};
        var device: Device = .{ .storage = &store, .ack_lost_once = timeout, .mismatch_once = !timeout };
        if (timeout) try expectError(error.HidTimeout, ctl.execute(&device, &store, cyan)) else try expectError(error.ReadbackMismatch, ctl.execute(&device, &store, cyan));
        try eql(u8, &fixture().state, &device.state);
        try expect(device.writes == 2 and store.journal == null);
    }
}
test "Air75 foreign ownership and unowned changes retain recovery without overwriting edits" {
    var store: Storage = .{};
    var device: Device = .{ .storage = &store, .change_unowned = true };
    try expectError(error.UnownedLightingChanged, ctl.execute(&device, &store, cyan));
    try expect(device.writes == 1 and store.journal.?.pending);
    device.info.state = device.state;
    try expectError(error.UnownedLightingChanged, ctl.execute(&device, &store, null));
    try expect(device.writes == 1);
    device.info = fixture();
    device.state = fixture().state;
    device.fingerprint[0] = 'b';
    try expectError(error.RecoveryIdentityMismatch, ctl.execute(&device, &store, null));
    try expect(device.writes == 1);
}
test "Air75 concurrent configuration and disconnection stop before a setter" {
    var store: Storage = .{};
    var device: Device = .{ .storage = &store, .concurrent = true };
    try expectError(error.ConcurrentDeviceChange, ctl.execute(&device, &store, cyan));
    try expect(device.writes == 0 and store.journal.?.pending);
    device = .{ .storage = &store, .disconnect = true };
    try expectError(error.DeviceDisconnected, ctl.restoreExact(&device, fixture().state));
    try expect(device.writes == 0);
}
test "Air75 exact RGB restoration requires a proven projection before alternate encoding" {
    var target = fixture().state;
    target[6..9].* = .{ 64, 0, 17 };
    var device: Device = .{};
    const restored = try ctl.restoreExact(&device, target);
    try eql(u8, &target, &restored);
    try expect(device.writes == 2);
    device = .{ .direct = true };
    _ = try ctl.restoreExact(&device, target);
    try expect(device.writes == 1);
    var store: Storage = .{};
    device = .{ .storage = &store };
    const purple = try ctl.execute(&device, &store, .{ .color = .{ .r = 128, .g = 0, .b = 255 }, .brightness = 15 });
    try eql(u8, &.{ 132, 0, 255 }, purple.state[6..9]);
}
test "Air75 saved capture rejects unsupported originals and survives JSON roundtrip" {
    var info = fixture();
    for ([_]u8{ 0, 21, 22, 255 }) |mode| {
        info.state[0] = mode;
        try expectError(error.UnsupportedOriginalEffect, ctl.recoverable(info.state));
    }
    info = fixture();
    info.profile = 1;
    try expectError(error.UnverifiedProfile, ctl.writable(info));
    info = fixture();
    info.firmware[0] += 1;
    try expectError(error.UnverifiedAir75Firmware, ctl.writable(info));
    const journal = ctl.Journal{ .fingerprint = @splat('a'), .original = fixture(), .expected = fixture().state };
    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, journal, .{});
    defer std.testing.allocator.free(json);
    const parsed = try std.json.parseFromSlice(ctl.Journal, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try parsed.value.validate(fixture(), @splat('a'));
    try eql(u8, &fixture().state, &parsed.value.original.state);
    var corrupt = journal;
    corrupt.expected[21] ^= 1;
    try expectError(error.InvalidRecoveryRecord, corrupt.validate(fixture(), @splat('a')));
}
test "Air75 main envelope contains nine bytes and never touches side or preset offsets" {
    const wire = [_]u8{ 3, 15, 2, 0, 0, 4, 128, 0, 255 };
    const frame = try ctl.writeFrame(wire, 0x80);
    try std.testing.expectEqual(protocol.checksum(frame), frame[3]);
    try std.testing.expectEqual(@as(u8, 9), frame[4] ^ 0x80);
    for (frame[17..]) |byte| try expect(byte == 0);
    var invalid = wire;
    invalid[0] = 21;
    try expectError(error.UnsupportedOriginalEffect, ctl.writeFrame(invalid, 0x80));
}
