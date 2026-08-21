const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const golden = @import("test_util/golden.zig");
const config = @import("config");

pub fn main() !void {}

const PAGE_SIZE: usize = 4096; // WARNING: hardcoded to 4096
const BTREE_HEADER_SIZE: usize = 16;

const HeaderPage = struct {
    magic: [10]u8,
    version: u8,
    pageSize: u16,
    pageCount: u32,
    rootPageID: u32,
    reserved: [4075]u8,
};

const EncodingError = error{
    Unrecoverable,
    PageFull,
};

// asserts that size of page is 4096 bytes
fn encodeHeaderPage(page: HeaderPage) EncodingError![PAGE_SIZE]u8 {
    if (!std.mem.eql(u8, &page.magic, "PUNK_DB_01")) {
        return EncodingError.Unrecoverable;
    }

    var buffer: [PAGE_SIZE]u8 = [_]u8{0} ** 4096;
    var w = std.Io.Writer.fixed(&buffer);

    w.writeAll(&page.magic) catch unreachable;
    w.writeByte(page.version) catch unreachable;
    w.writeInt(u16, page.pageSize, .little) catch unreachable;
    w.writeInt(u32, page.pageCount, .little) catch unreachable;
    w.writeInt(u32, page.rootPageID, .little) catch unreachable;
    w.writeAll(&page.reserved) catch unreachable;

    return buffer;
}

test encodeHeaderPage {
    // Succes case
    var page: HeaderPage = .{
        .magic = "PUNK_DB_01".*,
        .version = 1,
        .pageSize = PAGE_SIZE,
        .pageCount = 1,
        .rootPageID = 0,
        .reserved = [_]u8{0} ** 4075,
    };

    const encoded_page = try encodeHeaderPage(page);

    try expectEqual(PAGE_SIZE, encoded_page.len);
    try expectEqualSlices(u8, "PUNK_DB_01", encoded_page[0..10]);
    try expectEqual(@as(u8, 1), encoded_page[10]);
    try expectEqual(@as(u16, PAGE_SIZE), std.mem.readInt(u16, encoded_page[11..13], .little));
    try expectEqual(@as(u32, 1), std.mem.readInt(u32, encoded_page[13..17], .little));
    try expectEqual(@as(u32, 0), std.mem.readInt(u32, encoded_page[17..21], .little));
    try expectEqualSlices(u8, &page.reserved, encoded_page[21..]);

    // Golden case
    if (config.write_golden) {
        golden.writeGolden(&encoded_page, "header_page.golden");
    }

    var buffer: [4096]u8 = golden.readGolden("header_page.golden");
    try expectEqualSlices(u8, &encoded_page, &buffer);

    // Invalid magic must be rejected.
    page.magic = "spookerror".*;
    try std.testing.expectError(EncodingError.Unrecoverable, encodeHeaderPage(page));
}

// 16 bytes
const BTreePageHeader = struct {
    pageType: u8,
    cellsCount: u16,
    startOffset: u16,
    rightMostChildPageID: u32,
    reserved: [7]u8,
};

const InternalCell = struct {
    key: u32,
    childPageID: u32,
};

const Offset = u16;

// B-Tree page structure is Header -> Offset array -> ?freespace -> cells
// TODO: Currently we are using fixed sized integers for the key, update to allow Strings too
fn encodeInteriorPage(cells: []const InternalCell) ![PAGE_SIZE]u8 {
    const CELL_SIZE = 8; //TODO: Change from constant when we do update on keys

    var cell_cursor = PAGE_SIZE;
    var offset_cursor = BTREE_HEADER_SIZE;
    var page = [_]u8{0} ** 4096;

    for (cells) |cell| {
        // Write each cell from the bottom up
        cell_cursor -= CELL_SIZE;
        std.mem.writeInt(u32, page[cell_cursor..][0..4], cell.key, .little);
        std.mem.writeInt(u32, page[cell_cursor + 4 ..][0..4], cell.childPageID, .little);

        // Check for collision
        if (BTREE_HEADER_SIZE + offset_cursor + 2 > cell_cursor) {
            return EncodingError.PageFull;
        }

        // Write the offset
        std.mem.writeInt(u16, page[offset_cursor..][0..2], CELL_SIZE, .little);
        offset_cursor += @sizeOf(u16); // TODO: Change hardcoded cell size
    }
    // Write header
    const test_header: BTreePageHeader = .{
        .pageType = 1,
        .cellsCount = @intCast(cells.len),
        .startOffset = @intCast(cell_cursor),
        .rightMostChildPageID = 3,
        .reserved = [_]u8{0} ** 7,
    };

    var w = std.Io.Writer.fixed(&page);
    try w.writeInt(u8, test_header.pageType, .little);
    try w.writeInt(u16, test_header.cellsCount, .little);
    try w.writeInt(u16, test_header.startOffset, .little);
    try w.writeInt(u32, test_header.rightMostChildPageID, .little);
    try w.writeAll(&test_header.reserved);

    return page;
}

test encodeInteriorPage {
    const cell1: InternalCell = .{
        .key = 2,
        .childPageID = 1,
    };

    const cell2: InternalCell = .{
        .key = 3,
        .childPageID = 2,
    };

    const cells = [_]InternalCell{ cell1, cell2 };
    const encoded_page = try encodeInteriorPage(&cells);
    // Success case: the page contains the expected header, offsets, and cells.
    try expectEqual(@as(u8, 1), encoded_page[0]);
    try expectEqual(@as(u16, 2), std.mem.readInt(u16, encoded_page[1..3], .little));
    try expectEqual(@as(u16, 4080), std.mem.readInt(u16, encoded_page[3..5], .little));
    try expectEqual(@as(u32, 3), std.mem.readInt(u32, encoded_page[5..9], .little));
    try expectEqualSlices(u8, &[_]u8{0} ** 7, encoded_page[9..16]);

    try expectEqual(@as(u16, 8), std.mem.readInt(u16, encoded_page[16..18], .little));
    try expectEqual(@as(u16, 8), std.mem.readInt(u16, encoded_page[18..20], .little));

    try expectEqual(@as(u32, 3), std.mem.readInt(u32, encoded_page[4080..4084], .little));
    try expectEqual(@as(u32, 2), std.mem.readInt(u32, encoded_page[4084..4088], .little));
    try expectEqual(@as(u32, 2), std.mem.readInt(u32, encoded_page[4088..4092], .little));
    try expectEqual(@as(u32, 1), std.mem.readInt(u32, encoded_page[4092..4096], .little));

    // Golden case
    if (config.write_golden) {
        golden.writeGolden(&encoded_page, "btree_page.golden");
    }

    var buffer: [4096]u8 = golden.readGolden("btree_page.golden");
    try expectEqualSlices(u8, &encoded_page, &buffer);
}
