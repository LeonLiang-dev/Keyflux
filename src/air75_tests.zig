const std = @import("std");
const air = @import("air75.zig");
const s4 = @import("nuphy_s4.zig");
const protocol = @import("protocol.zig");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const Mock = struct {
    calls: usize = 0,
    key: u8 = 0x80,
    profile: u8 = 0,
    wrong_firmware: bool = false,
    wrong_geometry: bool = false,
    bad_count: bool = false,
    corrupt: bool = false,
    wrong_route: bool = false,
    change_profile: bool = false,
    change_session: bool = false,
    bad_descriptor: bool = false,
    pub fn descriptor(self: *Mock, out: []u8) !usize {
        const bytes = [_]u8{ 0x75, 8, 0x95, 64, 0x81, 2, 0x91, 2 };
        @memcpy(out[0..bytes.len], &bytes);
        if (self.bad_descriptor) out[3] = 63;
        return bytes.len;
    }
    pub fn exchange(self: *Mock, request: protocol.Report, key: u8) !protocol.Report {
        const sequence = [_]u8{ 0xa1, 0xa0, 0xd1, 0xd5, 0xa0, 0xa1 };
        try expect(self.calls < sequence.len);
        try std.testing.expectEqual(sequence[self.calls], request[1]);
        self.calls += 1;
        try std.testing.expectEqual(protocol.checksum(request), request[3]);
        for (request[8..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
        const actual_key = if (self.change_session and self.calls == 6) self.key ^ 1 else self.key;
        var reply: protocol.Report = @splat(0);
        reply[0] = 0xaa;
        reply[1] = request[1];
        var length: usize = 8;
        var payload: [56]u8 = @splat(0);
        var profile: u8 = 0;
        switch (request[1]) {
            0xa1 => payload[0..8].* = .{ if (self.wrong_firmware) 24 else 23, 0, 1, 0xaa, 6, 0, 0, 0 },
            0xa0 => payload[0..8].* = .{ if (self.change_profile and self.calls == 5) self.profile ^ 1 else self.profile, 8, 4, 6, if (self.wrong_geometry) 15 else 16, 0x82, 0, 0 },
            0xd1 => {
                length = 1;
                payload[0] = if (self.bad_count) 85 else 104;
            },
            0xd5 => {
                length = 22;
                profile = self.profile;
                try std.testing.expectEqual(self.profile, request[7] ^ key);
                for (payload[0..22], 0..) |*byte, i| byte.* = @intCast(i);
                payload[21] = 94; // Observed read-only preset parameter; retain verbatim.
            },
            else => return error.ForbiddenCommand,
        }
        reply[4..8].* = .{ @as(u8, @intCast(length)), 0, 0, profile };
        // Exercise masked as well as plaintext response routing.
        if (self.calls % 2 == 0) for (reply[4..8]) |*byte| {
            byte.* ^= actual_key;
        };
        for (0..length) |i| reply[8 + i] = payload[i] ^ actual_key;
        if (self.wrong_route) reply[6] ^= 1;
        reply[3] = protocol.checksum(reply);
        if (self.corrupt) reply[3] ^= 1;
        return reply;
    }
};

test "Air75 probe reads six queries, preserves 22 bytes and never exposes session data" {
    for ([_]u8{ 0, 1 }) |profile| {
        var mock: Mock = .{ .profile = profile };
        const info = try air.inspect(&mock);
        try expect(info.read_only and !info.main_write_enabled);
        try std.testing.expectEqual(@as(usize, 6), mock.calls);
        try std.testing.expectEqual(@as(u8, 104), info.led_count);
        try std.testing.expectEqual(@as(u8, 94), info.state[21]);
        try std.testing.expectEqual(@as(usize, 6), info.firmware.len);
        try std.testing.expectEqual(@as(usize, 6), info.geometry.len);
        const json = try std.json.Stringify.valueAlloc(std.testing.allocator, info, .{});
        defer std.testing.allocator.free(json);
        for ([_][]const u8{ "\"key\"", "serial", "fingerprint", "location", "path" }) |private|
            try expect(std.mem.indexOf(u8, json, private) == null);
    }
}

test "Air75 query codec restricts profiles and never constructs a setter payload" {
    inline for ([_]air.Command{ .firmware, .geometry, .led_count, .lighting }) |command| {
        const request = try air.frame(command, 0, if (command == .firmware) 0 else 0x80);
        for (request[8..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
        try expectError(error.ForbiddenCommand, air.frame(command, 2, 0));
        if (command != .lighting) try expectError(error.ForbiddenCommand, air.frame(command, 1, 0));
    }
    try expectError(error.ForbiddenCommand, air.frame(.firmware, 0, 1));
    const d5 = try air.frame(.lighting, 1, 0x80);
    try std.testing.expectEqual(@as(u8, 22), d5[4] ^ 0x80);
}

test "Air75 rejects malformed replies and unknown hardware before proceeding" {
    var mock: Mock = .{ .corrupt = true };
    try expectError(error.InvalidReport, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 1), mock.calls);
    mock = .{ .wrong_route = true };
    try expectError(error.RouteMismatch, air.inspect(&mock));
    mock = .{ .wrong_firmware = true };
    try expectError(error.UnverifiedAir75Firmware, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 1), mock.calls);
    mock = .{ .wrong_geometry = true };
    try expectError(error.UnverifiedAir75Geometry, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 2), mock.calls);
    mock = .{ .bad_count = true };
    try expectError(error.UnverifiedAir75LedCount, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 3), mock.calls);
    mock = .{ .bad_descriptor = true };
    try expectError(error.UnsupportedHidDescriptor, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 0), mock.calls);
    try expectError(error.InvalidReport, s4.decode(@splat(0), 0xd5, 22, 0, 0, 0));
}

test "Air75 rejects profile and session changes instead of returning a mixed snapshot" {
    var mock: Mock = .{ .change_profile = true };
    try expectError(error.ProfileChanged, air.inspect(&mock));
    try std.testing.expectEqual(@as(usize, 5), mock.calls);
    mock = .{ .change_session = true };
    try expectError(error.DeviceSessionChanged, air.inspect(&mock));
}
