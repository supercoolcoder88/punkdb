const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const golden = @import("test_util/golden.zig");
const config = @import("config");

pub fn main() !void {}

const PAGE_SIZE: usize = 4096; // WARNING: hardcoded to 4096

const HeaderPage = struct {
    magic: [10]u8,
    version: u8,
    pageSize: u16,
    pageCount: u32,
    rootPageId: u32,
    reserved: [4075]u8,
};

const EncodingError = error{
    Unrecoverable,
};

// asserts that size of page is 4096 bytes
fn encodeHeaderPage(page: HeaderPage) EncodingError![PAGE_SIZE]u8 {
    if (!std.mem.eql(u8, &page.magic, "PUNK_DB_01")) {
        return EncodingError.Unrecoverable;
    }

    var buffer: [PAGE_SIZE]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);

    w.writeAll(&page.magic) catch unreachable;
    w.writeByte(page.version) catch unreachable;
    w.writeInt(u16, page.pageSize, .little) catch unreachable;
    w.writeInt(u32, page.pageCount, .little) catch unreachable;
    w.writeInt(u32, page.rootPageId, .little) catch unreachable;
    w.writeAll(&page.reserved) catch unreachable;

    return buffer;
}

test encodeHeaderPage {
    // Golden case
    var page: HeaderPage = .{
        .magic = "PUNK_DB_01".*,
        .version = 1,
        .pageSize = PAGE_SIZE,
        .pageCount = 1,
        .rootPageId = 0,
        .reserved = [_]u8{0} ** 4075,
    };

    const encoded_page = try encodeHeaderPage(page);

    if (config.write_golden) {
        golden.writeGolden(&encoded_page, "header_page.golden");
    }

    var buffer: [4096]u8 = golden.readGolden("header_page.golden");
    try expectEqualSlices(u8, &encoded_page, &buffer);

    // Invalid magic must be rejected.
    page.magic = "spookerror".*;
    try std.testing.expectError(EncodingError.Unrecoverable, encodeHeaderPage(page));
}

const BTreePageHeader = struct {
    pageType: u8,
    cellsCount: u16,
    startOffset: u16,
    childPageId: u32,
    reserved: [7]u8,
};

// B-Tree page structure is Header -> Offset array -> ?freespace -> cells
