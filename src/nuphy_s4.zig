//! Shared, pure HID descriptor and S4 response validation. No device access.
const protocol = @import("protocol.zig");
pub const ReportShape = struct { input: u16 = 0, output: u16 = 0 };
pub fn reportShape(bytes: []const u8) !ReportShape {
    var size: u32 = 0;
    var count: u32 = 0;
    var shape: ReportShape = .{};
    var i: usize = 0;
    while (i < bytes.len) {
        const tag = bytes[i];
        i += 1;
        if (tag == 0xfe) return error.UnsupportedHidDescriptor;
        const length: usize = switch (tag & 3) {
            3 => 4,
            else => tag & 3,
        };
        if (length > bytes.len - i) return error.InvalidHidDescriptor;
        var value: u32 = 0;
        for (bytes[i..][0..length], 0..) |b, shift| value |= @as(u32, b) << @as(u5, @intCast(shift * 8));
        i += length;
        switch (tag & 0xfc) {
            0x74 => size = value,
            0x94 => count = value,
            0x84, 0xa4, 0xb4 => return error.UnsupportedHidDescriptor,
            0x80, 0x90 => {
                const bits = @as(u64, size) * count;
                if (bits > 8192 or bits % 8 != 0) return error.InvalidHidDescriptor;
                const total = @as(u64, if ((tag & 0xfc) == 0x80) shape.input else shape.output) + bits / 8;
                if (total > 1024) return error.InvalidHidDescriptor;
                if ((tag & 0xfc) == 0x80) shape.input = @intCast(total) else shape.output = @intCast(total);
            },
            else => {},
        }
    }
    if (shape.input != 64 or shape.output != 64) return error.UnsupportedHidDescriptor;
    return shape;
}
pub fn decode(raw: protocol.Report, command: u8, length: u8, address: u16, profile: u8, key: u8) ![56]u8 {
    if (length > 56 or raw[0] != 0xaa or raw[1] != command or raw[2] != 0 or raw[3] != protocol.checksum(raw)) return error.InvalidReport;
    const route = [4]u8{ length, @truncate(address), @truncate(address >> 8), profile };
    var plain = true;
    var masked = true;
    for (route, raw[4..8]) |want, got| {
        plain = plain and want == got;
        masked = masked and want == (got ^ key);
    }
    if (!plain and !masked) return error.RouteMismatch;
    var result: [56]u8 = @splat(0);
    for (0..length) |i| result[i] = raw[8 + i] ^ key;
    return result;
}
