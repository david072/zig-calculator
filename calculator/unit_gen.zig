const std = @import("std");

const Writer = std.io.Writer(std.fs.File, std.os.WriteError, std.fs.File.write);

var units: std.ArrayList([]const u8) = undefined;

/// Generates `/calculator/src/units.zig` from `/calculator/units.txt`
/// This file provides functions for the engine to convert units
pub fn generate() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    units = std.ArrayList([]const u8).init(gpa.allocator());
    defer units.deinit();

    const file = try std.fs.cwd().openFile("./calculator/units.txt", .{});
    defer file.close();

    const output_file = try std.fs.cwd().createFile("./calculator/src/units.zig", .{});
    defer output_file.close();

    const reader = file.reader();
    const writer = output_file.writer();

    _ = try writer.write("// Generated from ../units.txt by ../unit_gen.zig during build step.\n");

    _ = try writer.write("const std = @import(\"std\");\n");

    _ = try writer.write(
        \\
        \\ // "da" is currently not supported, however we need it as a spacer
        \\const unit_prefixes = [_][]const u8{"n", "m", "c", "d", "none", "da", "h", "k", "M", "g", "t"};
        \\fn indexOfUnitPrefix(prefix: []const u8) ?usize {
        \\    for (unit_prefixes) |u, i|
        \\        if (std.mem.eql(u8, u, prefix)) return i;
        \\    return null;
        \\}
        \\
        \\const ResultStruct = struct {
        \\    source_start_index: usize,
        \\    target_start_index: usize,
        \\};
        \\
        \\fn normalizeUnits(num: *f32, source_unit: []const u8, target_unit: []const u8) ResultStruct {
        \\    var source_prefix: usize = 4;
        \\    var target_prefix: usize = 4;
        \\
        \\    if (source_unit.len > 1)
        \\        source_prefix = indexOfUnitPrefix(&[_]u8{source_unit[0]}) orelse return ResultStruct{ .source_start_index = 0, .target_start_index = 0 };
        \\    if (target_unit.len > 1)
        \\        target_prefix = indexOfUnitPrefix(&[_]u8{target_unit[0]}) orelse return ResultStruct{ .source_start_index = 0, .target_start_index = 0 };
        \\    
        \\    if (source_prefix == target_prefix) return ResultStruct{ .source_start_index = 0, .target_start_index = 0 };
        \\    const target_value = unit_prefixes[target_prefix];
        \\
        \\    const incrementor: i8 = if (target_prefix > source_prefix) 1 else -1;
        \\    var index = source_prefix;
        \\    while (true) : ({
        \\        if (incrementor > 0) {
        \\            index += 1;
        \\        } else {
        \\            index -= 1;
        \\        }
        \\    }) {
        \\        if (std.mem.eql(u8, target_value, unit_prefixes[index])) break;
        \\        // If we're going up the list (getting to greater "prefix-values"), we want to reduce the value
        \\        num.* *= if (incrementor > 0) 0.1 else @as(f32, 10);
        \\    }
        \\
        \\    return ResultStruct{ 
        \\        .source_start_index = if (source_prefix == 4) 0 else 1, 
        \\        .target_start_index = if (target_prefix == 4) 0 else 1, 
        \\    };
        \\}
    );

    _ = try writer.write(
        \\pub fn convert(number: f32, source_unit: []const u8, target_unit: []const u8) ?f32 {
        \\    var n: f32 = number;
        \\    const start_indices = normalizeUnits(&n, source_unit, target_unit);
        \\    const source_start_index = start_indices.source_start_index;
        \\    const target_start_index = start_indices.target_start_index;
        \\
        \\    if (std.mem.eql(u8, source_unit[source_start_index..], target_unit[target_start_index..])) return n;
        \\
    );

    _ = try writer.write("\n");

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0 or line.len == 1) continue;
        if (line[0] == '#') continue;

        if (line[0] == '-') {
            try writeRemainingUnits(gpa.allocator(), line, &writer);
            break;
        }

        try writeUnitFromLine(gpa.allocator(), line, &writer);
    }

    _ = try writer.write("return null;\n");
    _ = try writer.write("}\n");

    try writeValidUnitsFunction(gpa.allocator(), &writer);
}

fn writeUnitFromLine(allocator: std.mem.Allocator, line: []const u8, writer: *const Writer) !void {
    var _function_name = std.ArrayList(u8).init(allocator);
    var _source_unit_name = std.ArrayList(u8).init(allocator);
    var _target_unit_name = std.ArrayList(u8).init(allocator);

    var did_find_source_unit_name = false;

    var return_value: []const u8 = undefined;

    for (line) |char, i| {
        switch (char) {
            '_' => {
                did_find_source_unit_name = true;
                try _function_name.append(char);
            },
            '=' => {
                return_value = line[i + 1 ..];
                break;
            },
            ' ' => continue,
            else => {
                try _function_name.append(char);
                if (!did_find_source_unit_name) {
                    try _source_unit_name.append(char);
                } else try _target_unit_name.append(char);
            },
        }
    }

    const function_name = _function_name.toOwnedSlice();
    defer allocator.free(function_name);

    // source_unit_name is freed in writeValidUnitsFunction
    const source_unit_name = _source_unit_name.toOwnedSlice();

    const target_unit_name = _target_unit_name.toOwnedSlice();
    defer allocator.free(target_unit_name);

    try writer.print("if (std.mem.eql(u8, source_unit[source_start_index..], \"{s}\") and std.mem.eql(u8, target_unit[target_start_index..], \"{s}\")) ", .{ source_unit_name, target_unit_name });
    _ = try writer.write("{\n");
    try writer.print("    return {s};\n", .{return_value});
    _ = try writer.write("}\n");

    try units.append(source_unit_name);
}

fn writeRemainingUnits(allocator: std.mem.Allocator, line: []const u8, writer: *const Writer) !void {
    var unit = std.ArrayList(u8).init(allocator);
    defer unit.deinit();

    for (line) |char| {
        switch (char) {
            ' ', '-' => continue,
            ',' => {
                if (unit.items.len == 0) continue;
                try writer.print("if (std.mem.eql(u8, source_unit[source_start_index..], \"{s}\") and std.mem.eql(u8, target_unit[target_start_index..], \"{s}\")) return n;\n", .{ unit.items, unit.items });
                // Will later be freed by writeValidUnitsFunction
                try addValidUnit(unit.toOwnedSlice());
            },
            else => try unit.append(char),
        }
    }

    if (unit.items.len > 0) {
        try writer.print("if (std.mem.eql(u8, source_unit[source_start_index..], \"{s}\") and std.mem.eql(u8, target_unit[target_start_index..], \"{s}\")) return n;", .{ unit.items, unit.items });
        // Will later be freed by writeValidUnitsFunction
        try addValidUnit(unit.toOwnedSlice());
    }
}

fn addValidUnit(unit: []const u8) !void {
    for (units.items) |item|
        if (std.mem.eql(u8, item, unit)) return;

    try units.append(unit);
}

fn writeValidUnitsFunction(allocator: std.mem.Allocator, writer: *const Writer) !void {
    _ = try writer.write("\nconst valid_units = [_][]const u8{");

    var index: usize = 0;
    while (index < units.items.len) : (index += 1) {
        try writer.print("\"{s}\",", .{units.items[index]});
        allocator.free(units.items[index]);
    }

    _ = try writer.write("};\n");
    _ = try writer.write(
        \\pub fn isUnit(str: []const u8) bool {
        \\    inline for (valid_units) |unit| {
        \\        if (std.mem.eql(u8, unit, str)) {
        \\            return true;
        \\        } else {
        \\            if (str.len > 1 and indexOfUnitPrefix(&[_]u8{str[0]}) != null and std.mem.eql(u8, unit, str[1..])) return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
    );
}
