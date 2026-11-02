//! Air75 V3 read-only probe. Manual mutations live in air75_control.zig.
const std = @import("std");
const p = @import("platform.zig");
const protocol = @import("protocol.zig");
const s4 = @import("nuphy_s4.zig");

pub const Command = enum(u8) { firmware = 0xa1, geometry = 0xa0, led_count = 0xd1, lighting = 0xd5 };
pub const Probe = struct {
    schema_version: u8 = 1,
    model_id: []const u8 = "nuphy-air75-v3",
    name: []const u8 = "NuPhy Air75 V3 ANSI",
    read_only: bool = true,
    main_write_enabled: bool = false,
    firmware_version: []const u8 = "1.0.23.6",
    // A1 and A0 trailing bytes are session/reserved data, not public identity.
    firmware: [6]u8,
    geometry: [6]u8,
    profile: u8,
    profile_name: []const u8,
    led_count: u8,
    state: [22]u8,
    state_bytes: u8 = 22,
    usb: struct { vendor_id: u16 = 0x19f5, product_id: u16 = 0x1028, interface_number: u8 = 3, usage_page: u8 = 1, usage: u8 = 0, input_bytes: u16 = 64, output_bytes: u16 = 64 } = .{},
};

pub fn frame(command: Command, profile: u8, key: u8) !protocol.Report {
    if (profile > 1 or (command != .lighting and profile != 0)) return error.ForbiddenCommand;
    if (command == .firmware and key != 0) return error.ForbiddenCommand;
    const length: u8 = switch (command) {
        .firmware, .geometry => 8,
        .led_count => 1,
        .lighting => 22,
    };
    var result: protocol.Report = @splat(0);
    result[0] = 0x55;
    result[1] = @backingInt(command);
    result[4] = length ^ key;
    result[5] = key;
    result[6] = key;
    result[7] = profile ^ key;
    result[3] = protocol.checksum(result);
    return result;
}

pub fn firmware(raw: protocol.Report) !struct { key: u8, bytes: [8]u8 } {
    const key = raw[11] ^ 0xaa;
    const bytes = try s4.decode(raw, 0xa1, 8, 0, 0, key);
    if (!std.mem.eql(u8, bytes[0..6], &.{ 23, 0, 1, 0xaa, 6, 0 })) return error.UnverifiedAir75Firmware;
    return .{ .key = key, .bytes = bytes[0..8].* };
}

pub fn validateGeometry(bytes: [8]u8) !void {
    if (bytes[0] > 1 or !std.mem.eql(u8, bytes[1..5], &.{ 8, 4, 6, 16 }) or
        (bytes[5] & 0x80 != 0 and bytes[5] & 0x7f != 2)) return error.UnverifiedAir75Geometry;
}

pub fn inspect(transport: anytype) !Probe {
    var descriptor: [2048]u8 = undefined;
    const count = try transport.descriptor(&descriptor);
    if (count == 0 or count > descriptor.len) return error.InvalidHidDescriptor;
    _ = try s4.reportShape(descriptor[0..count]);
    const identity = try firmware(try transport.exchange(try frame(.firmware, 0, 0), 0));
    const key = identity.key;
    const geometry = (try s4.decode(try transport.exchange(try frame(.geometry, 0, key), key), 0xa0, 8, 0, 0, key))[0..8].*;
    try validateGeometry(geometry);
    const leds = try s4.decode(try transport.exchange(try frame(.led_count, 0, key), key), 0xd1, 1, 0, 0, key);
    if (leds[0] != 104) return error.UnverifiedAir75LedCount;
    const state = try s4.decode(try transport.exchange(try frame(.lighting, geometry[0], key), key), 0xd5, 22, 0, geometry[0], key);
    // Preserve every state byte, including unverified preset parameters. Never
    // normalize this diagnostic snapshot or treat it as a writable capture.
    const after = try s4.decode(try transport.exchange(try frame(.geometry, 0, key), key), 0xa0, 8, 0, 0, key);
    if (!std.mem.eql(u8, geometry[0..6], after[0..6])) return error.ProfileChanged;
    const final = try firmware(try transport.exchange(try frame(.firmware, 0, 0), 0));
    if (final.key != key or !std.mem.eql(u8, identity.bytes[0..6], final.bytes[0..6])) return error.DeviceSessionChanged;
    return .{ .firmware = identity.bytes[0..6].*, .geometry = geometry[0..6].*, .profile = geometry[0], .profile_name = if (geometry[0] == 0) "mac" else "win", .led_count = leds[0], .state = state[0..22].* };
}

pub const Native = struct {
    key: u8 = 0,
    pub fn descriptor(_: *Native, out: []u8) !usize {
        const n = p.kf_air75_descriptor(out.ptr, out.len);
        if (n <= 0) return error.InvalidHidDescriptor;
        return @intCast(n);
    }
    pub fn exchange(self: *Native, request: protocol.Report, key: u8) !protocol.Report {
        var reply: protocol.Report = undefined;
        switch (p.kf_air75_exchange(&request, &reply, key)) {
            0 => {
                if (request[1] == 0xa1) self.key = (try firmware(reply)).key;
                return reply;
            },
            -7 => return error.ForbiddenCommand,
            -8 => return error.HidWriteFailed,
            -9 => return error.DeviceDisconnected,
            -10 => return error.HidTimeout,
            else => return error.HidExchangeFailed,
        }
    }
    pub fn write(_: *Native, request: protocol.Report, key: u8) !protocol.Report {
        var reply: protocol.Report = undefined;
        switch (p.kf_air75_write_main(&request, &reply, key)) {
            0 => return reply,
            -7 => return error.ForbiddenCommand,
            -8 => return error.HidWriteFailed,
            -9 => return error.DeviceDisconnected,
            -10 => return error.HidTimeout,
            else => return error.HidExchangeFailed,
        }
    }
};

pub fn open() !void {
    switch (p.kf_air75_open()) {
        0 => {},
        -2 => return error.DeviceBusy,
        -3 => return error.DeviceNotFound,
        -4 => return error.MultipleDevices,
        -5 => return error.UnsupportedPlatform,
        else => return error.HidOpenFailed,
    }
}
pub fn probe() !Probe {
    try open();
    defer p.kf_air75_close();
    var native: Native = .{};
    return inspect(&native);
}
