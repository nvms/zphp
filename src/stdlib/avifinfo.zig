// libavifinfo as php 8.5 bundles it (ext/standard/libavifinfo/avifinfo.c):
// the streamed api getimagesize uses to identify avif files and read the
// primary item's size, bit depth and channels
const std = @import("std");

pub const max_num_read_bytes = 64;

pub const Features = struct {
    width: u32 = 0,
    height: u32 = 0,
    bit_depth: u32 = 0,
    num_channels: u32 = 0,
    has_gainmap: u8 = 0,
    gainmap_item_id: u8 = 0,
    primary_item_id_location: u64 = 0,
    primary_item_id_bytes: u8 = 0,
};

const Status = enum { found, not_found, truncated, aborted, invalid };

const max_size: u32 = std.math.maxInt(u32);
const max_num_boxes = 4096;
const max_value = 255;
const max_tiles = 16;
const max_props = 32;
const max_features = 8;

fn readBigEndian(input: []const u8, num_bytes: u32) u32 {
    var value: u32 = 0;
    for (input[0..num_bytes]) |b| value = (value << 8) | b;
    return value;
}

fn Stream(comptime S: type) type {
    return struct {
        user: S,
        num_read_bytes: u64 = 0,

        const Self = @This();

        fn read(self: *Self, n: u32, data: *[]const u8) Status {
            data.* = self.user.read(n) orelse return .truncated;
            self.num_read_bytes += n;
            return .found;
        }

        fn skip(self: *Self, n: u32) Status {
            if (n > 0) {
                self.user.skip(n);
                self.num_read_bytes += n;
            }
            return .found;
        }
    };
}

const Tile = struct { tile_item_id: u8 = 0, parent_item_id: u8 = 0, dimg_idx: u8 = 0 };
const Prop = struct { property_index: u8 = 0, item_id: u8 = 0 };
const DimProp = struct { property_index: u8 = 0, width: u32 = 0, height: u32 = 0 };
const ChanProp = struct { property_index: u8 = 0, bit_depth: u8 = 0, num_channels: u8 = 0 };

const Internal = struct {
    has_primary_item: bool = false,
    has_alpha: bool = false,
    gainmap_property_index: u8 = 0,
    primary_item_id: u8 = 0,
    primary_item_features: Features = .{},
    data_was_skipped: bool = false,
    tone_mapped_item_id: u8 = 0,
    iinf_parsed: bool = false,
    iref_parsed: bool = false,
    num_tiles: u8 = 0,
    tiles: [max_tiles]Tile = @splat(.{}),
    num_props: u8 = 0,
    props: [max_props]Prop = @splat(.{}),
    num_dim_props: u8 = 0,
    dim_props: [max_features]DimProp = @splat(.{}),
    num_chan_props: u8 = 0,
    chan_props: [max_features]ChanProp = @splat(.{}),
};

fn getItemFeatures(f: *Internal, target_item_id: u32, tile_depth: u32) Status {
    for (f.props[0..f.num_props]) |prop| {
        if (prop.item_id != target_item_id) continue;
        const property_index = prop.property_index;
        if (target_item_id == f.primary_item_id and (f.primary_item_features.width == 0 or f.primary_item_features.height == 0)) {
            for (f.dim_props[0..f.num_dim_props]) |dp| {
                if (dp.property_index != property_index) continue;
                f.primary_item_features.width = dp.width;
                f.primary_item_features.height = dp.height;
                if (f.primary_item_features.bit_depth != 0 and f.primary_item_features.num_channels != 0) return .found;
                break;
            }
        }
        if (f.primary_item_features.bit_depth == 0 or f.primary_item_features.num_channels == 0) {
            for (f.chan_props[0..f.num_chan_props]) |cp| {
                if (cp.property_index != property_index) continue;
                f.primary_item_features.bit_depth = cp.bit_depth;
                f.primary_item_features.num_channels = cp.num_channels;
                if (f.primary_item_features.width != 0 and f.primary_item_features.height != 0) return .found;
                break;
            }
        }
    }
    if (tile_depth < 3) {
        for (f.tiles[0..f.num_tiles]) |tile| {
            if (tile.parent_item_id != target_item_id) continue;
            const s = getItemFeatures(f, tile.tile_item_id, tile_depth + 1);
            if (s != .not_found) return s;
        }
    }
    return .not_found;
}

fn getPrimaryItemFeatures(f: *Internal) Status {
    if (!f.has_primary_item) return .not_found;
    if (!(f.num_dim_props > 0 and f.num_chan_props > 0)) return .not_found;
    if (f.tone_mapped_item_id != 0) {
        for (f.tiles[0..f.num_tiles]) |tile| {
            if (tile.parent_item_id == f.tone_mapped_item_id and tile.dimg_idx == 1) {
                f.primary_item_features.has_gainmap = 1;
                f.primary_item_features.gainmap_item_id = tile.tile_item_id;
                break;
            }
        }
    }
    if (f.primary_item_features.has_gainmap == 0 and f.gainmap_property_index > 0) {
        for (f.props[0..f.num_props]) |prop| {
            if (prop.property_index == f.gainmap_property_index) {
                f.primary_item_features.has_gainmap = 1;
                f.primary_item_features.gainmap_item_id = prop.item_id;
                break;
            }
        }
    }
    if (f.primary_item_features.has_gainmap == 0 and (!f.iinf_parsed or (f.tone_mapped_item_id != 0 and !f.iref_parsed))) return .not_found;
    const s = getItemFeatures(f, f.primary_item_id, 0);
    if (s != .found) return s;
    if (f.has_alpha) f.primary_item_features.num_channels += 1;
    return .found;
}

const Box = struct {
    size: u32 = 0,
    type: [4]u8 = undefined,
    version: u32 = 0,
    flags: u32 = 0,
    content_size: u32 = 0,

    fn is(self: Box, t: []const u8) bool {
        return std.mem.eql(u8, &self.type, t);
    }
};

fn Parser(comptime S: type) type {
    return struct {
        const St = Stream(S);

        fn parseBox(nesting_level: u32, stream: *St, num_remaining_bytes: u32, num_parsed_boxes: *u32, box: *Box) Status {
            var data: []const u8 = undefined;
            var header_size: u32 = 8;
            if (header_size > num_remaining_bytes) return .invalid;
            if (stream.read(8, &data) != .found) return .truncated;
            box.size = readBigEndian(data, 4);
            @memcpy(&box.type, data[4..8]);
            if (box.size == 1) {
                header_size += 8;
                if (header_size > num_remaining_bytes) return .invalid;
                if (stream.read(8, &data) != .found) return .truncated;
                if (readBigEndian(data, 4) != 0) return .aborted;
                box.size = readBigEndian(data[4..], 4);
            } else if (box.size == 0) {
                if (nesting_level != 0) return .invalid;
                box.size = num_remaining_bytes;
            }
            if (box.size < header_size) return .invalid;
            if (box.size > num_remaining_bytes) return .invalid;
            const full = box.is("meta") or box.is("pitm") or box.is("ipma") or box.is("ispe") or
                box.is("pixi") or box.is("iref") or box.is("auxC") or box.is("iinf") or box.is("infe");
            if (full) header_size += 4;
            if (box.size < header_size) return .invalid;
            box.content_size = box.size - header_size;
            if (nesting_level != 0 or !box.is("ftyp")) {
                num_parsed_boxes.* += 1;
                if (num_parsed_boxes.* >= max_num_boxes) return .aborted;
            }
            box.version = 0;
            box.flags = 0;
            if (full) {
                const s = stream.read(4, &data);
                if (s != .found) return s;
                box.version = readBigEndian(data, 1);
                box.flags = readBigEndian(data[1..], 3);
                const parsable = (box.is("meta") and box.version <= 0) or
                    (box.is("pitm") and box.version <= 1) or
                    (box.is("ipma") and box.version <= 1) or
                    (box.is("ispe") and box.version <= 0) or
                    (box.is("pixi") and box.version <= 0) or
                    (box.is("iref") and box.version <= 1) or
                    (box.is("auxC") and box.version <= 0) or
                    (box.is("iinf") and box.version <= 1) or
                    (box.is("infe") and box.version >= 2 and box.version <= 3);
                if (!parsable) box.type = "skip".*;
            }
            return .found;
        }

        fn parseIpco(nesting_level: u32, stream: *St, remaining_in: u32, num_parsed_boxes: *u32, features: *Internal) Status {
            var num_remaining_bytes = remaining_in;
            var box_index: u32 = 1;
            while (true) {
                var box: Box = .{};
                var s = parseBox(nesting_level, stream, num_remaining_bytes, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("ispe")) {
                    var data: []const u8 = undefined;
                    if (box.content_size < 8) return .invalid;
                    s = stream.read(8, &data);
                    if (s != .found) return s;
                    const width = readBigEndian(data, 4);
                    const height = readBigEndian(data[4..], 4);
                    if (width == 0 or height == 0) return .invalid;
                    if (features.num_dim_props < max_features and box_index <= max_value) {
                        features.dim_props[features.num_dim_props] = .{ .property_index = @intCast(box_index), .width = width, .height = height };
                        features.num_dim_props += 1;
                    } else features.data_was_skipped = true;
                    s = stream.skip(box.content_size - 8);
                    if (s != .found) return s;
                } else if (box.is("pixi")) {
                    var data: []const u8 = undefined;
                    if (box.content_size < 1) return .invalid;
                    s = stream.read(1, &data);
                    if (s != .found) return s;
                    const num_channels = readBigEndian(data, 1);
                    if (num_channels < 1) return .invalid;
                    if (box.content_size < 1 + num_channels) return .invalid;
                    s = stream.read(1, &data);
                    if (s != .found) return s;
                    const bit_depth = readBigEndian(data, 1);
                    if (bit_depth < 1) return .invalid;
                    var i: u32 = 1;
                    while (i < num_channels) : (i += 1) {
                        s = stream.read(1, &data);
                        if (s != .found) return s;
                        if (readBigEndian(data, 1) != bit_depth) return .invalid;
                        if (i > 32) return .aborted;
                    }
                    if (features.num_chan_props < max_features and box_index <= max_value and bit_depth <= max_value and num_channels <= max_value) {
                        features.chan_props[features.num_chan_props] = .{ .property_index = @intCast(box_index), .bit_depth = @intCast(bit_depth), .num_channels = @intCast(num_channels) };
                        features.num_chan_props += 1;
                    } else features.data_was_skipped = true;
                    s = stream.skip(box.content_size - (1 + num_channels));
                    if (s != .found) return s;
                } else if (box.is("av1C")) {
                    var data: []const u8 = undefined;
                    if (box.content_size < 3) return .invalid;
                    s = stream.read(3, &data);
                    if (s != .found) return s;
                    const high = data[2] & 0x40 != 0;
                    const twelve = data[2] & 0x20 != 0;
                    const mono = data[2] & 0x10 != 0;
                    if (twelve and !high) return .invalid;
                    if (features.num_chan_props < max_features and box_index <= max_value) {
                        features.chan_props[features.num_chan_props] = .{ .property_index = @intCast(box_index), .bit_depth = if (high) (if (twelve) 12 else 10) else 8, .num_channels = if (mono) 1 else 3 };
                        features.num_chan_props += 1;
                    } else features.data_was_skipped = true;
                    s = stream.skip(box.content_size - 3);
                    if (s != .found) return s;
                } else if (box.is("auxC")) {
                    const alpha = "urn:mpeg:mpegB:cicp:systems:auxiliary:alpha";
                    const alpha_len: u32 = 44;
                    const gainmap = "urn:com:photo:aux:hdrgainmap";
                    const gainmap_len: u32 = 29;
                    var num_read: u32 = 0;
                    if (box.content_size >= gainmap_len) {
                        var data: []const u8 = undefined;
                        s = stream.read(gainmap_len, &data);
                        if (s != .found) return s;
                        num_read = gainmap_len;
                        // strcmp: up to the first nul
                        const aux = std.mem.sliceTo(data, 0);
                        if (std.mem.eql(u8, aux, gainmap)) {
                            if (box_index <= max_value) features.gainmap_property_index = @intCast(box_index) else features.data_was_skipped = true;
                        } else if (box.content_size >= alpha_len and std.mem.eql(u8, data[0..gainmap_len], alpha[0..gainmap_len])) {
                            var data2: []const u8 = undefined;
                            s = stream.read(alpha_len - gainmap_len, &data2);
                            if (s != .found) return s;
                            num_read = alpha_len;
                            if (std.mem.eql(u8, std.mem.sliceTo(data2, 0), alpha[gainmap_len..])) features.has_alpha = true;
                        }
                    }
                    s = stream.skip(box.content_size - num_read);
                    if (s != .found) return s;
                } else {
                    s = stream.skip(box.content_size);
                    if (s != .found) return s;
                }
                box_index += 1;
                num_remaining_bytes -= box.size;
                if (num_remaining_bytes == 0) break;
            }
            return .not_found;
        }

        fn parseIprp(nesting_level: u32, stream: *St, remaining_in: u32, num_parsed_boxes: *u32, features: *Internal) Status {
            var num_remaining_bytes = remaining_in;
            while (true) {
                var box: Box = .{};
                var s = parseBox(nesting_level, stream, num_remaining_bytes, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("ipco")) {
                    s = parseIpco(nesting_level + 1, stream, box.content_size, num_parsed_boxes, features);
                    if (s != .not_found) return s;
                } else if (box.is("ipma")) {
                    var num_read: u32 = 4;
                    var data: []const u8 = undefined;
                    if (box.content_size < num_read) return .invalid;
                    s = stream.read(4, &data);
                    if (s != .found) return s;
                    const entry_count = readBigEndian(data, 4);
                    const id_bytes: u32 = if (box.version < 1) 2 else 4;
                    const index_bytes: u32 = if (box.flags & 1 != 0) 2 else 1;
                    const essential_mask: u32 = if (box.flags & 1 != 0) 0x8000 else 0x80;
                    var entry: u32 = 0;
                    while (entry < entry_count) : (entry += 1) {
                        if (entry >= max_props or features.num_props >= max_props) {
                            features.data_was_skipped = true;
                            break;
                        }
                        num_read += id_bytes + 1;
                        if (box.content_size < num_read) return .invalid;
                        s = stream.read(id_bytes + 1, &data);
                        if (s != .found) return s;
                        const item_id = readBigEndian(data, id_bytes);
                        const association_count = readBigEndian(data[id_bytes..], 1);
                        var property: u32 = 0;
                        while (property < association_count) : (property += 1) {
                            if (property >= max_props or features.num_props >= max_props) {
                                features.data_was_skipped = true;
                                break;
                            }
                            num_read += index_bytes;
                            if (box.content_size < num_read) return .invalid;
                            s = stream.read(index_bytes, &data);
                            if (s != .found) return s;
                            const value = readBigEndian(data, index_bytes);
                            const property_index = value & ~essential_mask;
                            if (property_index <= max_value and item_id <= max_value) {
                                features.props[features.num_props] = .{ .property_index = @intCast(property_index), .item_id = @intCast(item_id) };
                                features.num_props += 1;
                            } else features.data_was_skipped = true;
                        }
                        if (property < association_count) break;
                    }
                    s = getPrimaryItemFeatures(features);
                    if (s != .not_found) return s;
                    s = stream.skip(box.content_size - num_read);
                    if (s != .found) return s;
                } else {
                    s = stream.skip(box.content_size);
                    if (s != .found) return s;
                }
                num_remaining_bytes -= box.size;
                if (num_remaining_bytes == 0) break;
            }
            return .not_found;
        }

        fn parseIref(nesting_level: u32, stream: *St, remaining_in: u32, num_parsed_boxes: *u32, features: *Internal) Status {
            var num_remaining_bytes = remaining_in;
            features.iref_parsed = true;
            while (num_remaining_bytes > 0) {
                var box: Box = .{};
                var s = parseBox(nesting_level, stream, num_remaining_bytes, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("dimg")) {
                    const id_bytes: u32 = if (box.version == 0) 2 else 4;
                    var num_read: u32 = id_bytes + 2;
                    var data: []const u8 = undefined;
                    if (box.content_size < num_read) return .invalid;
                    s = stream.read(id_bytes + 2, &data);
                    if (s != .found) return s;
                    const from_item_id = readBigEndian(data, id_bytes);
                    const reference_count = readBigEndian(data[id_bytes..], 2);
                    var i: u32 = 0;
                    while (i < reference_count) : (i += 1) {
                        if (i >= max_tiles) {
                            features.data_was_skipped = true;
                            break;
                        }
                        num_read += id_bytes;
                        if (box.content_size < num_read) return .invalid;
                        s = stream.read(id_bytes, &data);
                        if (s != .found) return s;
                        const to_item_id = readBigEndian(data, id_bytes);
                        if (from_item_id <= max_value and to_item_id <= max_value and features.num_tiles < max_tiles) {
                            features.tiles[features.num_tiles] = .{ .tile_item_id = @intCast(to_item_id), .parent_item_id = @intCast(from_item_id), .dimg_idx = @intCast(i) };
                            features.num_tiles += 1;
                        } else features.data_was_skipped = true;
                    }
                    s = getPrimaryItemFeatures(features);
                    if (s != .not_found) return s;
                    s = stream.skip(box.content_size - num_read);
                    if (s != .found) return s;
                } else {
                    s = stream.skip(box.content_size);
                    if (s != .found) return s;
                }
                num_remaining_bytes -= box.size;
            }
            return .not_found;
        }

        fn parseIinf(nesting_level: u32, stream: *St, remaining_in: u32, box_version: u32, num_parsed_boxes: *u32, features: *Internal) Status {
            var num_remaining_bytes = remaining_in;
            features.iinf_parsed = true;
            const count_bytes: u32 = if (box_version == 0) 2 else 4;
            if (count_bytes > num_remaining_bytes) return .invalid;
            var data: []const u8 = undefined;
            var s = stream.read(count_bytes, &data);
            if (s != .found) return s;
            num_remaining_bytes -= count_bytes;
            const entry_count = readBigEndian(data, count_bytes);
            // the loop counter is an int in the c code
            var i: i64 = 0;
            while (i < entry_count) : (i += 1) {
                var box: Box = .{};
                s = parseBox(nesting_level, stream, num_remaining_bytes, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("infe")) {
                    const id_bytes: u32 = if (box.version == 2) 2 else 4;
                    if (id_bytes + 2 + 4 > box.content_size) return .invalid;
                    s = stream.read(id_bytes, &data);
                    if (s != .found) return s;
                    const item_id = readBigEndian(data, id_bytes);
                    s = stream.skip(2);
                    if (s != .found) return s;
                    var item_type: []const u8 = undefined;
                    s = stream.read(4, &item_type);
                    if (s != .found) return s;
                    if (std.mem.eql(u8, item_type[0..4], "tmap")) {
                        if (item_id <= max_value) features.tone_mapped_item_id = @intCast(item_id) else features.data_was_skipped = true;
                    }
                    s = stream.skip(box.content_size - (id_bytes + 2 + 4));
                    if (s != .found) return s;
                } else {
                    s = stream.skip(box.content_size);
                    if (s != .found) return s;
                }
                num_remaining_bytes -= box.size;
                if (num_remaining_bytes == 0) break;
            }
            return .not_found;
        }

        fn parseMeta(nesting_level: u32, stream: *St, remaining_in: u32, num_parsed_boxes: *u32, features: *Internal) Status {
            var num_remaining_bytes = remaining_in;
            while (true) {
                var box: Box = .{};
                var s = parseBox(nesting_level, stream, num_remaining_bytes, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("pitm")) {
                    const id_bytes: u32 = if (box.version == 0) 2 else 4;
                    const location = stream.num_read_bytes;
                    var data: []const u8 = undefined;
                    if (id_bytes > num_remaining_bytes) return .invalid;
                    s = stream.read(id_bytes, &data);
                    if (s != .found) return s;
                    const primary = readBigEndian(data, id_bytes);
                    if (primary > max_value) return .aborted;
                    features.has_primary_item = true;
                    features.primary_item_id = @intCast(primary);
                    features.primary_item_features.primary_item_id_location = location;
                    features.primary_item_features.primary_item_id_bytes = @intCast(id_bytes);
                    s = stream.skip(box.content_size -% id_bytes);
                    if (s != .found) return s;
                } else if (box.is("iprp")) {
                    s = parseIprp(nesting_level + 1, stream, box.content_size, num_parsed_boxes, features);
                    if (s != .not_found) return s;
                } else if (box.is("iref")) {
                    s = parseIref(nesting_level + 1, stream, box.content_size, num_parsed_boxes, features);
                    if (s != .not_found) return s;
                } else if (box.is("iinf")) {
                    s = parseIinf(nesting_level + 1, stream, box.content_size, box.version, num_parsed_boxes, features);
                    if (s != .not_found) return s;
                } else {
                    s = stream.skip(box.content_size);
                    if (s != .found) return s;
                }
                num_remaining_bytes -= box.size;
                if (num_remaining_bytes == 0) break;
            }
            return if (features.data_was_skipped) .aborted else .invalid;
        }

        fn parseFtyp(stream: *St) Status {
            var box: Box = .{};
            var num_parsed_boxes: u32 = 0;
            var s = parseBox(0, stream, max_size, &num_parsed_boxes, &box);
            if (s != .found) return s;
            if (!box.is("ftyp")) return .invalid;
            if (box.content_size < 8) return .invalid;
            var i: u32 = 0;
            while (i + 4 <= box.content_size) : (i += 4) {
                var data: []const u8 = undefined;
                s = stream.read(4, &data);
                if (s != .found) return s;
                if (i == 4) continue;
                if (std.mem.eql(u8, data[0..4], "avif") or std.mem.eql(u8, data[0..4], "avis")) {
                    s = stream.skip(box.content_size - (i + 4));
                    if (s != .found) return s;
                    return .found;
                }
                if (i > 32 * 4) return .aborted;
            }
            return .invalid;
        }

        fn parseFile(stream: *St, num_parsed_boxes: *u32, features: *Internal) Status {
            while (true) {
                var box: Box = .{};
                var s = parseBox(0, stream, max_size, num_parsed_boxes, &box);
                if (s != .found) return s;
                if (box.is("meta")) return parseMeta(1, stream, box.content_size, num_parsed_boxes, features);
                s = stream.skip(box.content_size);
                if (s != .found) return s;
            }
        }
    };
}

// AvifInfoIdentifyStream == kAvifInfoOk
pub fn identifyStream(user: anytype) bool {
    const P = Parser(@TypeOf(user));
    var stream: P.St = .{ .user = user };
    return P.parseFtyp(&stream) == .found;
}

// AvifInfoGetFeaturesStream: the features when it returns kAvifInfoOk
pub fn getFeaturesStream(user: anytype) ?Features {
    const P = Parser(@TypeOf(user));
    var stream: P.St = .{ .user = user };
    var num_parsed_boxes: u32 = 0;
    var internal: Internal = .{};
    if (P.parseFile(&stream, &num_parsed_boxes, &internal) != .found) return null;
    return internal.primary_item_features;
}
