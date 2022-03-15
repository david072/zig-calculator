const std = @import("std");

const Writer = std.io.Writer(std.fs.File, std.os.WriteError, std.fs.File.write);

/// Generates `/calculator/src/units.zig` from `/calculator/units.txt`
/// This file provides functions for the engine to convert units
pub fn generate() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const file = try std.fs.cwd().openFile("./calculator/units.txt", .{});
    defer file.close();

    const output_file = try std.fs.cwd().createFile("./calculator/src/units.zig", .{});
    defer output_file.close();

    const reader = file.reader();
    const writer = output_file.writer();

    _ = try writer.write("// Generated from ../units.txt by ../unit_gen.zig during build step.\n");

    _ = try writer.write("const std = @import(\"std\");\n");
    _ = try writer.write("pub fn convert(n: f32, source_unit: []const u8, target_unit: []const u8) ?f32 {\n");

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line[0] == '#') continue;
        try writeFunction(gpa.allocator(), line, &writer);
    }

    _ = try writer.write("return null;\n");
    _ = try writer.write("}\n");

    // TODO: Add a function to tell whether a unit string is a valid unit
}

fn writeFunction(allocator: std.mem.Allocator, line: []const u8, writer: *const Writer) !void {
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

    const source_unit_name = _source_unit_name.toOwnedSlice();
    defer allocator.free(source_unit_name);

    const target_unit_name = _target_unit_name.toOwnedSlice();
    defer allocator.free(target_unit_name);

    try writer.print("if (std.mem.eql(u8, source_unit, \"{s}\") and std.mem.eql(u8, target_unit, \"{s}\")) ", .{ source_unit_name, target_unit_name });
    _ = try writer.write("{\n");
    try writer.print("    return {s};\n", .{return_value});
    _ = try writer.write("}\n");

    // try writer.print("pub fn {s}({s}: anytype) @TypeOf({s})", .{ function_name, variable_name, variable_name });
    // _ = try writer.write(" {\n");
    // try writer.print("return {s};\n", .{return_value});
    // _ = try writer.write("}\n");
}
