const std = @import("std");
const ArrayList = std.ArrayList;

const ast = @import("./ast.zig");
const AstNode = ast.AstNode;

const calc_context = @import("calc_context.zig");
const units = @import("units.zig");

const numbers = "1234567890";
const letters = "abcdefghijklmnopqrstuvwxyz";

const ParsingError = error{
    ExpectedOperand,
    ExpectedOperator,
    MissingBracket,

    UnknownVariable,
    UnknownUnit,
    UnknownDeclaration,

    ExpectedParameter,
    ExpectedEqualsSign,

    /// std.fmt.ParseFloatError
    Overflow,
    InvalidCharacter,

    /// Allocator error
    OutOfMemory,
};

const GroupStartIndex = struct {
    index: usize,
    is_function: bool,
    function_name: ?[]const u8,
};

pub var errorIndex: usize = undefined;

pub fn parse(allocator: std.mem.Allocator, _input: []const u8) ParsingError!?[]AstNode {
    const input = std.mem.trim(u8, _input, " ");
    if (std.mem.startsWith(u8, input, "def:")) {
        // parseDeclaration adds a new function or variable declaration to calc_context
        parseDeclaration(allocator, input[4..]) catch |err| {
            errorIndex += 4;
            return err;
        };
        return null;
    } else if (std.mem.startsWith(u8, input, "undef:")) {
        // Collects the name and removes either a variable or function declaration
        removeDeclaration(allocator, input[6..]) catch |err| {
            errorIndex += 6;
            return err;
        };
        return null;
    }

    const allowed_variables = try getAllowedVariables(allocator, &[_][]u8{});
    defer allocator.free(allowed_variables);
    return try parseEquation(allocator, input, allowed_variables);
}

pub fn removeDeclaration(allocator: std.mem.Allocator, input: []const u8) ParsingError!void {
    var name = ArrayList(u8).init(allocator);
    errdefer name.deinit();

    for (input) |char| {
        switch (char) {
            'a'...'z', '_' => try name.append(char),
            ' ', '\r', '\n' => continue,
            else => return ParsingError.InvalidCharacter,
        }
    }

    const declaration_name = name.toOwnedSlice();
    if (calc_context.getFunctionDeclarationIndex(declaration_name)) |index| {
        _ = calc_context.function_declarations.orderedRemove(index);
    } else {
        if (calc_context.getVariableDeclarationIndex(declaration_name)) |index| {
            _ = calc_context.variable_declarations.orderedRemove(index);
        } else return ParsingError.UnknownDeclaration;
    }
}

pub fn parseDeclaration(allocator: std.mem.Allocator, input: []const u8) ParsingError!void {
    const lasting_allocator = calc_context.lastingAllocator();

    var name = ArrayList(u8).init(lasting_allocator);
    errdefer name.deinit();

    var parameters = try lasting_allocator.alloc([]u8, 1);
    parameters[0] = try lasting_allocator.alloc(u8, 1);
    var parameter_index: usize = 0;
    var parameter_item_index: usize = 0;

    var is_parsing_function_name = true;

    for (input) |char, i| {
        switch (char) {
            'a'...'z', '_' => {
                if (is_parsing_function_name) {
                    try name.append(char);
                } else {
                    if (parameter_item_index >= parameters[parameter_index].len)
                        parameters[parameter_index] = try lasting_allocator.realloc(parameters[parameter_index], parameters[parameter_index].len + 1);
                    parameters[parameter_index][parameter_item_index] = char;
                    parameter_item_index += 1;
                }
            },
            '(' => is_parsing_function_name = false,
            ')' => {
                if (parameter_item_index == 0) {
                    errorIndex = i;
                    return ParsingError.ExpectedParameter;
                }

                var index = i + 1;
                while (index < input.len and input[index] != '=') : (index += 1) {}

                if (index == input.len) {
                    errorIndex = input.len - 1;
                    return ParsingError.ExpectedEqualsSign;
                }

                const allowed_variables = try getAllowedVariables(allocator, parameters);
                defer allocator.free(allowed_variables);

                const equation = parseEquation(lasting_allocator, input[index + 1 ..], allowed_variables) catch |err| {
                    errorIndex += index + 1;
                    return err;
                };

                const function_decl_index = calc_context.getFunctionDeclarationIndex(name.items);

                try calc_context.function_declarations.append(.{
                    .function_name = name.toOwnedSlice(),
                    .parameters = parameters,
                    .equation = equation,
                });

                if (function_decl_index != null) {
                    calc_context.function_declarations.items[function_decl_index.?].free(lasting_allocator);
                    _ = calc_context.function_declarations.swapRemove(function_decl_index.?);
                }
                return;
            },
            ',' => {
                parameter_index += 1;
                parameter_item_index = 0;
                parameters = try lasting_allocator.realloc(parameters, parameters.len + 1);
                parameters[parameter_index] = try lasting_allocator.alloc(u8, 1);
            },
            '=' => {
                // If we reach this, it's a variable declaration,
                // since when it's a function declarations the '=' is skipped
                const variable_name = name.toOwnedSlice();

                const allowed_variables = try getAllowedVariables(allocator, &[_][]u8{variable_name});
                defer allocator.free(allowed_variables);

                const equation = parseEquation(lasting_allocator, input[i + 1 ..], allowed_variables) catch |err| {
                    errorIndex += i + 1;
                    return err;
                };

                const variable_decl_index = calc_context.getVariableDeclarationIndex(variable_name);

                try calc_context.variable_declarations.append(.{
                    .variable_name = variable_name,
                    .equation = equation,
                });

                if (variable_decl_index != null) {
                    calc_context.variable_declarations.items[variable_decl_index.?].free(lasting_allocator);
                    _ = calc_context.variable_declarations.swapRemove(variable_decl_index.?);
                }
                return;
            },
            ' ' => continue,
            else => {
                errorIndex = i;
                return ParsingError.InvalidCharacter;
            },
        }
    }

    return ParsingError.MissingBracket;
}

pub fn parseEquation(allocator: std.mem.Allocator, input: []const u8, allowed_variables: []const []const u8) ParsingError![]AstNode {
    errorIndex = 0;

    var tree = ArrayList(AstNode).init(allocator);
    var number = ArrayList(u8).init(allocator);

    var groupStartIndices = ArrayList(GroupStartIndex).init(allocator);
    defer groupStartIndices.deinit();

    errdefer {
        tree.deinit();
        number.deinit();
    }

    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        const char = input[index];

        switch (char) {
            '\r', '\n' => {
                if (tree.items.len > 0 and tree.items[tree.items.len - 1].nodeType == .Operand) return ParsingError.ExpectedOperator;

                if (number.items.len > 0) {
                    var nextNode = try makeOperand(allocator, number.toOwnedSlice(), allowed_variables);
                    try tree.append(nextNode);
                    errorIndex = index + 1;
                }
            },
            '(' => {
                errorIndex = index;
                if (index != 0 and std.mem.containsAtLeast(u8, letters, 1, &[_]u8{input[index - 1]})) {
                    var _function_name = ArrayList(u8).init(allocator);

                    var i: usize = index - 1;
                    while (i >= 0 and (input[i] == '_' or std.mem.containsAtLeast(u8, letters, 1, &[_]u8{input[i]}))) {
                        try _function_name.append(input[i]);
                        if (i == 0) break;
                        i -= 1;
                    }

                    var function_name = try allocator.alloc(u8, _function_name.items.len);
                    i = _function_name.items.len - 1;
                    var function_name_index: usize = 0;
                    while (i >= 0) : ({
                        function_name_index += 1;
                    }) {
                        function_name[function_name_index] = _function_name.items[i];
                        if (i == 0) break;
                        i -= 1;
                    }

                    try groupStartIndices.append(.{ .index = tree.items.len, .is_function = true, .function_name = function_name });
                    _function_name.deinit();
                    // I think I'm safe to do this?
                    number.clearAndFree();
                    continue;
                }

                if (number.items.len != 0) return ParsingError.ExpectedOperator;
                try groupStartIndices.append(.{ .index = tree.items.len, .is_function = false, .function_name = null });
            },
            ')' => {
                errorIndex = index;
                if (number.items.len > 0) {
                    var nextNode = try makeOperand(allocator, number.toOwnedSlice(), allowed_variables);
                    try tree.append(nextNode);
                    errorIndex = index + 1;
                }

                const groupStartIndex = groupStartIndices.items[groupStartIndices.items.len - 1];

                var group = ArrayList(AstNode).init(allocator);
                var i: usize = groupStartIndex.index;
                while (i < tree.items.len) {
                    const removedItem = tree.orderedRemove(i);
                    try group.append(removedItem);
                }

                if (group.items.len == 0) return ParsingError.ExpectedOperand;

                var nextNode: AstNode = undefined;
                if (groupStartIndex.is_function) {
                    var parameters = try allocator.alloc([]AstNode, 1);
                    parameters[0] = try allocator.alloc(AstNode, 1);

                    i = 0;
                    var item_index: usize = 0;
                    for (group.items) |item| {
                        if (item.nodeType == .Separator) {
                            i += 1;
                            item_index = 0;
                            parameters = try allocator.realloc(parameters, parameters.len + 1);
                            parameters[i] = try allocator.alloc(AstNode, 1);
                            continue;
                        }

                        if (item_index >= parameters[i].len)
                            parameters[i] = try allocator.realloc(parameters[i], parameters[i].len + 1);

                        parameters[i][item_index] = item;
                        item_index += 1;
                    }

                    nextNode = AstNode{
                        .nodeType = .FunctionCall,
                        .value = .{
                            .function_call = .{
                                .function_name = groupStartIndex.function_name.?,
                                .parameters = parameters,
                            },
                        },
                    };
                } else {
                    nextNode = AstNode{
                        .nodeType = .Group,
                        .value = .{
                            .children = group.toOwnedSlice(),
                        },
                    };
                }

                try tree.append(nextNode);
                _ = groupStartIndices.orderedRemove(groupStartIndices.items.len - 1);
            },
            ',' => {
                if (groupStartIndices.items.len > 0 and groupStartIndices.items[groupStartIndices.items.len - 1].is_function) {
                    if (number.items.len > 0) {
                        var nextNode = try makeOperand(allocator, number.toOwnedSlice(), allowed_variables);
                        try tree.append(nextNode);
                        errorIndex = index + 1;
                    }
                    try tree.append(AstNode{ .nodeType = .Separator, .value = .{ .nothing = 0 } });
                } else return ParsingError.InvalidCharacter;
            },
            '+', '-', '*', '/' => {
                // Check if the '+' or '-' is the sign and if so, append it to the number.
                // It will later be handled by std.fmt.parseFloat
                if ((char == '+' or char == '-') and index + 1 < input.len) {
                    // Check if next char is a number and previous char is either unavailable or a space
                    if (std.mem.containsAtLeast(u8, numbers, 1, &[_]u8{input[index + 1]}) and
                        (index == 0 or !std.mem.containsAtLeast(u8, numbers, 1, &[_]u8{input[index - 1]})))
                    {
                        try number.append(char);
                        continue;
                    }
                }

                var nextNode: AstNode = undefined;
                if (number.items.len > 0) {
                    // Add number to AST
                    nextNode = try makeOperand(allocator, number.toOwnedSlice(), allowed_variables);
                    try tree.append(nextNode);
                    errorIndex = index + 1;
                }

                if (tree.items.len == 0 and number.items.len == 0) {
                    return ParsingError.ExpectedOperand;
                } else if (tree.items.len > 0 and tree.items[tree.items.len - 1].nodeType == .Operator) return ParsingError.ExpectedOperand;

                const operation: ast.Operation = switch (char) {
                    '+' => .Addition,
                    '-' => .Subtraction,
                    '*' => .Multiplication,
                    '/' => .Division,
                    else => continue,
                };

                // Add operation to AST
                nextNode = AstNode{
                    .nodeType = .Operator,
                    .value = .{
                        .operation = operation,
                    },
                };
                try tree.append(nextNode);
                errorIndex = index + 1;
            },
            ' ' => continue,
            else => {
                // Hackish. Checks for " in " (operator)
                if (char >= 'a' and char <= 'z' and index > 0) {
                    if (input[index - 1] == ' ' and input[index] == 'i' and input[index + 1] == 'n' and input[index + 2] == ' ') {
                        if (number.items.len > 0) {
                            // Add number to AST
                            try tree.append(try makeOperand(allocator, number.toOwnedSlice(), allowed_variables));
                            errorIndex = index + 1;
                        }

                        try tree.append(AstNode{
                            .nodeType = .Operator,
                            .value = .{ .operation = .Conversion },
                        });
                        index += 2;
                        continue;
                    }
                }

                try number.append(char);
            },
        }
    }

    if (groupStartIndices.items.len != 0) {
        errorIndex = input.len - 1;
        return ParsingError.MissingBracket;
    }

    if (number.items.len != 0) {
        if (tree.items.len > 0 and tree.items[tree.items.len - 1].nodeType == .Operand) return ParsingError.ExpectedOperator;

        var nextNode = try makeOperand(allocator, number.toOwnedSlice(), allowed_variables);
        try tree.append(nextNode);
    }

    return tree.toOwnedSlice();
}

/// Creates a AstNode with type Operand and the parsed number as the value.
/// It ensures `number` is freed, even if `std.fmt.parseFloat` fails.
/// If the number could not be parsed, it will create a variable reference node
fn makeOperand(allocator: std.mem.Allocator, number: []const u8, allowed_variables: []const []const u8) ParsingError!AstNode {
    const number_value = std.fmt.parseFloat(f64, number) catch null;

    // If number could not be parsed into a number, check if it is a valid variable name
    if (number_value == null) {
        if (try getUnitNode(allocator, number)) |node| return node;

        // TODO: Show proper error if it is neither a unit nor a variable
        if (units.isUnit(number)) {
            return AstNode{
                .nodeType = .Unit,
                .value = .{ .unit = number },
            };
        }

        if (!calc_context.isStandardVariable(number)) {
            const allowed = blk: {
                for (allowed_variables) |variable| {
                    if (std.mem.eql(u8, variable, number)) break :blk true;
                }
                break :blk false;
            };
            if (!allowed) return ParsingError.UnknownVariable;
        }
    }

    const result = AstNode{
        .nodeType = if (number_value != null) .Operand else .VariableReference,
        .value = if (number_value != null) .{
            .operand = .{ .number = number_value.? },
        } else .{
            .variable_name = number,
        },
    };

    if (number_value != null)
        allocator.free(number);
    return result;
}

/// Tries to construct an AstNode with a number and a unit
fn getUnitNode(allocator: std.mem.Allocator, unit_with_number: []const u8) !?AstNode {
    var _unit_number = ArrayList(u8).init(allocator);
    var unit = ArrayList(u8).init(allocator);
    var did_find_number = false;

    for (unit_with_number) |char| {
        switch (char) {
            '0'...'9', '.', '-', '+' => {
                if (did_find_number) return null;
                try _unit_number.append(char);
            },
            'a'...'z', 'A'...'Z', '_' => {
                if (_unit_number.items.len == 0) return null;
                did_find_number = true;
                try unit.append(char);
            },
            else => return null,
        }
    }

    if (!units.isUnit(unit.items)) {
        unit.deinit();
        _unit_number.deinit();
        return null;
    }

    const unit_number = _unit_number.toOwnedSlice();
    defer allocator.free(unit_number);

    return AstNode{
        .nodeType = .Operand,
        .value = .{
            .operand = .{
                .number = try std.fmt.parseFloat(f64, unit_number),
                .unit = unit.toOwnedSlice(),
            },
        },
    };
}

fn getAllowedVariables(allocator: std.mem.Allocator, additional_variables: []const []const u8) ![]const []const u8 {
    const allowed_variables = try allocator.alloc([]const u8, calc_context.variable_declarations.items.len + additional_variables.len);
    for (calc_context.variable_declarations.items) |_, index|
        allowed_variables[index] = calc_context.variable_declarations.items[index].variable_name;

    for (additional_variables) |_, index|
        allowed_variables[calc_context.variable_declarations.items.len + index] = additional_variables[index];

    return allowed_variables;
}
