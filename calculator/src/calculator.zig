const std = @import("std");

pub const parser = @import("astgen/parser.zig");
const engine = @import("engine.zig");
const context = @import("calc_context.zig");
const ast = @import("astgen/ast.zig");

const tokenizer = @import("astgen/tokenizer.zig");

var allocator: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
    context.init(allocator);
}

pub fn deinit() void {
    context.deinit();
}

pub fn calculate(input: []const u8) !?[]const u8 {
    // Create a ("one-time use") arena allocator. After the calculation
    // has finished, this helps freeing all "temporary" memory allocated during parsing
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    if (std.mem.startsWith(u8, input, "def:")) {
        try parser.parseDeclaration(arena.allocator(), input[4..]);
        return null;
    } else if (std.mem.startsWith(u8, input, "undef:")) {
        try parser.parseUnDeclaration(arena.allocator(), input[6..]);
        return null;
    }

    const tokens = try tokenizer.tokenize(arena.allocator(), input);
    const tree = try parser.parse(arena.allocator(), tokens);

    // dumpAst(tree, 0);

    const result = try engine.evaluate(arena.allocator(), tree.items);

    var buf: [100]u8 = undefined;
    const number = try std.fmt.bufPrint(&buf, "{d}", .{result.value.operand.number});

    var formattedResult = std.ArrayList(u8).init(allocator);
    try formattedResult.appendSlice(number);
    if (result.value.operand.unit != null) {
        const unit = try allocator.dupe(u8, result.value.operand.unit.?);
        try formattedResult.appendSlice(unit);
        allocator.free(unit);
    }

    return formattedResult.toOwnedSlice();
}

fn dumpAst(tree: []const ast.AstNode, nestingLevel: usize) void {
    for (tree) |item| {
        var i: usize = 0;
        while (i < nestingLevel) : (i += 1)
            std.debug.print("-", .{});

        std.debug.print(" type: {s}\n", .{item.nodeType});

        i = 0;
        while (i < nestingLevel) : (i += 1)
            std.debug.print(" ", .{});
        switch (item.nodeType) {
            .Group => {
                std.debug.print("   children: {d}\n", .{item.value.children.len});
                dumpAst(item.value.children, nestingLevel + 1);
            },
            .Operand => std.debug.print("   number: {d}, unit: {s}\n", .{ item.value.operand.number, item.value.operand.unit }),
            .Operator => std.debug.print("   operation: {s}\n", .{item.value.operation}),
            .FunctionCall => std.debug.print("   function: name: {s}, parameters: {s}\n", .{ item.value.function_call.function_name, item.value.function_call.parameters }),
            .VariableReference => std.debug.print("   variable: {s}\n", .{item.value.variable_name}),
            .Unit => std.debug.print("   unit: {s}\n", .{item.value.unit}),
            .Separator => unreachable,
        }
    }
}
