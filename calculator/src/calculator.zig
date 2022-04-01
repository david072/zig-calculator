const std = @import("std");

pub const parser = @import("astgen/parser.zig");
const engine = @import("engine.zig");
const context = @import("calc_context.zig");
const ast = @import("astgen/ast.zig");

const tokenizer = @import("astgen/tokenizer.zig");

pub const EvaluateDepth = enum {
    Tokenize,
    Parse,
    Calculate,
};

pub const Verbosity = enum {
    PrintTokens,
    PrintAst,
    PrintAll,
};

var allocator: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
    context.init(allocator);
}

pub fn deinit() void {
    context.deinit();
}

pub fn calculate(input: []const u8, evaluate_depth: ?EvaluateDepth, verbosity: ?Verbosity) !?[]const u8 {
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
    if (verbosity != null and (verbosity.? == .PrintTokens or verbosity.? == .PrintAll))
        for (tokens) |*token| std.debug.print("{s} -> {s}\n", .{ token.text, token.type });

    if (evaluate_depth != null and evaluate_depth.? != .Parse) return null;
    const tree = try parser.parse(arena.allocator(), tokens);

    if (verbosity != null and (verbosity.? == .PrintAst or verbosity.? == .PrintAll))
        dumpAst(tree, 0);

    if (evaluate_depth != null and evaluate_depth.? != .Calculate) return null;

    const result = try engine.calculate(arena.allocator(), tree);
    context.setLastValue(&result);

    var buf: [100]u8 = undefined;
    var formattedResult = std.ArrayList(u8).init(allocator);

    if (result.nodeType == .Boolean) {
        try formattedResult.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{result.value.boolean}));
    } else {
        try formattedResult.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{result.getNumberValue()}));
        if (result.value.operand.unit != null) {
            const unit = try allocator.dupe(u8, result.value.operand.unit.?);
            try formattedResult.appendSlice(unit);
            allocator.free(unit);
        }
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
            .Operand => std.debug.print("   number: {d}, unit: {s}, modifier: {s}\n", .{ item.value.operand.number, item.value.operand.unit, item.modifier }),
            .Operator => std.debug.print("   operation: {s}\n", .{item.value.operation}),
            .FunctionCall => {
                std.debug.print("   function: name: {s},\nparameters:\n", .{item.value.function_call.function_name});
                for (item.value.function_call.parameters) |*p| {
                    dumpAst(p.*, nestingLevel + 1);
                }
            },
            .VariableReference => std.debug.print("   variable: {s}\n", .{item.value.variable_name}),
            .Unit => std.debug.print("   unit: {s}\n", .{item.value.unit}),
            .Boolean => std.debug.print("   bool: {s}\n", .{item.value.boolean}),
            .EqualSign => {},
        }
    }
}
