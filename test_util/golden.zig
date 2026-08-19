const std = @import("std");

pub fn writeGolden(data: []const u8, comptime path: []const u8) void {
    const io = std.testing.io;
    const dir = std.Io.Dir.cwd();

    var file = std.Io.Dir.createFile(
        dir,
        io,
        "test_util/data/golden/" ++ path,
        .{},
    ) catch @panic("failed to create golden file");

    defer file.close(io);

    file.writeStreamingAll(io, data) catch @panic("failed to write golden file");
}

pub fn readGolden(comptime path: []const u8) [4096]u8 {
    const io = std.testing.io;

    var buffer: [4096]u8 = undefined;
    const read = std.Io.Dir.cwd().readFile(io, "test_util/data/golden/" ++ path, &buffer) catch @panic("failed to read");
    if (read.len != buffer.len) @panic("golden file has the wrong size");
    return buffer;
}
