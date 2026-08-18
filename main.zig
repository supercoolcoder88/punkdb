const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
pub fn main() !void {}

const PAGE_SIZE: usize = 4096;

const BTreePageHeader = struct {
    pageType: u8,
    cellsCount: u16,
    startOffset: u16,
    childPageId: u32,
    reserved: [7]u8,
};

const HeaderPage = struct {
    magic: [10]u8,
    version: u8,
    pageSize: u16,
    pageCount: u32,
    rootPageId: u32,
    reserved: [4075]u8,
};

// asserts that size of page is 4096 bytes
fn encodeHeaderPage(page: HeaderPage) [PAGE_SIZE]u8 {
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
    const page: HeaderPage = .{
        .magic = "PUNK_DB_01".*,
        .version = 1,
        .pageSize = PAGE_SIZE,
        .pageCount = 1,
        .rootPageId = 0,
        .reserved = [_]u8{0} ** 4075,
    };

    const encoded_page = encodeHeaderPage(page);
    try expectEqual(4096, encoded_page.len);
    try expectEqualSlices(u8, "PUNK_DB_01", encoded_page[0..10]);
    try expectEqual(@as(u8, 1), encoded_page[10]);
    try expectEqual(@as(u16, 4096), std.mem.readInt(u16, encoded_page[11..13], .little));
    try expectEqual(@as(u32, 1), std.mem.readInt(u32, encoded_page[13..17], .little));
    try expectEqual(@as(u32, 0), std.mem.readInt(u32, encoded_page[17..21], .little));
    try expectEqualSlices(u8, &([_]u8{0} ** 4075), encoded_page[21..encoded_page.len]);
}
