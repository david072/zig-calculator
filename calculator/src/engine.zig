const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const ast = @import("./ast.zig");
const AstNode = ast.AstNode;

const context = @import("./calc_context.zig");
const util = @import("../util/util.zig");

const units = @import("units.zig");

const CalculationError = error{
    InvalidSyntax,

    ExpectedOperand,
    ExpectedOperation,
    NotEnoughNodes,

    UnknownFunction,
    WrongParameters,

    UnknownVariable,

    // This error should never occur!!
    InvalidOperand,

    /// Allocation error
    OutOfMemory,

    NotImplemented,
};

/// Helper to convert degrees into radians
pub inline fn radians(degrees: f32) f32 {
    return (degrees / 360) * 2 * std.math.pi;
}

pub fn evaluate(allocator: Allocator, tree: []AstNode) CalculationError!f32 {
    // util.dumpAst(tree, 0);

    var currentNestingLevel: usize = 0;
    var deepestNestingLevel: usize = 0;
    var deepestNestedGroup: ?*AstNode = findDeepestNestedGroup(tree, &currentNestingLevel, &deepestNestingLevel);

    while (deepestNestedGroup != null) {
        const groupResult = try evaluateEquation(allocator, deepestNestedGroup.?.value.children);
        allocator.free(deepestNestedGroup.?.value.children);

        deepestNestedGroup.?.nodeType = .Operand;
        deepestNestedGroup.?.value = .{ .operand = .{ .number = groupResult } };

        currentNestingLevel = 0;
        deepestNestingLevel = 0;
        deepestNestedGroup = findDeepestNestedGroup(tree, &currentNestingLevel, &deepestNestingLevel);
    }

    return evaluateEquation(allocator, tree);
}

fn findDeepestNestedGroup(tree: []AstNode, currentNestingLevel: *usize, deepestNestingLevel: *usize) ?*AstNode {
    var deepestNestedGroup: ?*AstNode = null;

    // Why no use for loop zig :(
    var index: usize = 0;
    while (index < tree.len) : (index += 1) {
        var item = tree[index];
        if (item.nodeType != .Group) continue;

        currentNestingLevel.* += 1;

        const newDeepestNestedGroup = findDeepestNestedGroup(item.value.children, currentNestingLevel, deepestNestingLevel);
        if (currentNestingLevel.* > deepestNestingLevel.*) {
            deepestNestingLevel.* = currentNestingLevel.*;
        }

        currentNestingLevel.* -= 1;
        deepestNestedGroup = newDeepestNestedGroup orelse return &tree[index];
    }

    return deepestNestedGroup;
}

fn evaluateEquation(allocator: Allocator, originalEquation: []AstNode) CalculationError!f32 {
    try expandVariables(allocator, originalEquation);
    try evaluateFunctions(allocator, originalEquation);

    if (originalEquation.len == 1 and originalEquation[0].nodeType == .Operand) {
        return originalEquation[0].value.operand.number;
    } else if (originalEquation.len < 3) return CalculationError.NotEnoughNodes;

    const equation1 = try convertUnits(allocator, originalEquation);

    const equation = try evaluatePointCalculations(allocator, originalEquation);
    defer allocator.free(equation);

    allocator.free(equation1);

    if (equation.len == 1) {
        if (equation[0].nodeType != .Operand) return CalculationError.ExpectedOperand;
        return equation[0].value.operand.number;
    }

    var result: f32 = equation[0].value.operand.number;

    var index: usize = 0;
    while (index < equation.len) : (index += 2) {
        try validateCalculationPair(equation, index);

        const lhs = equation[index + 2].value.operand.number;

        switch (equation[index + 1].value.operation) {
            .Addition => result += lhs,
            .Subtraction => result -= lhs,
            else => continue,
        }

        if (index + 4 >= equation.len) break;
    }

    return result;
}

/// Converts all `AstNodes` with type `VariableReference` into an operand by evaluating the variable value.
/// It will return `CalculationError.UnknownVariable` if a variable is not in the `context.variable_declarations` list.
fn expandVariables(allocator: Allocator, tree: []AstNode) CalculationError!void {
    for (tree) |item, i| {
        if (item.nodeType != .VariableReference) continue;

        // Handle standard variables (e.g. e, pi)
        if (context.resolveStandardVariable(item.value.variable_name)) |value| {
            tree[i].nodeType = .Operand;
            tree[i].value = .{ .operand = .{ .number = value } };
            return;
        }

        // Otherwise look for user defined variable
        // TODO: Figure out why using getVariable doesn't work... (gpa error "Double free detected" useful?)
        // const defined_variable = context.getVariable(item.value.variable_name) orelse return CalculationError.UnknownVariable;
        const defined_variable = blk: {
            for (context.variable_declarations.items) |defined_variable| {
                if (std.mem.eql(u8, item.value.variable_name, defined_variable.variable_name))
                    break :blk &defined_variable;
            }
            return CalculationError.UnknownVariable;
        };

        tree[i].nodeType = .Operand;
        tree[i].value = .{ .operand = .{ .number = try evaluate(allocator, defined_variable.equation) } };
    }
}

/// Converts all `AstNodes` with type `FunctionCall` into an operand by evaluating the functions value.
/// It will return appropriate errors for unknown functions and wrong parameters (+ NotImplemented)
pub fn evaluateFunctions(allocator: Allocator, equation: []AstNode) CalculationError!void {
    var i: usize = 0;
    while (i < equation.len) : (i += 1) {
        const item = equation[i];
        if (item.nodeType != .FunctionCall) continue;

        const function_call = &item.value.function_call;
        const parameter = try evaluate(allocator, function_call.parameters[0]);

        var result: f32 = blk: {
            if (std.mem.eql(u8, function_call.function_name, "sin")) {
                // sin(param1)
                break :blk @sin(radians(parameter));
            } else if (std.mem.eql(u8, function_call.function_name, "cos")) {
                // cos(param1)
                break :blk @cos(radians(parameter));
            } else if (std.mem.eql(u8, function_call.function_name, "tan")) {
                // tan(param1)
                const rad = radians(parameter);
                break :blk @sin(rad) / @cos(rad);
            } else if (std.mem.eql(u8, function_call.function_name, "ln")) {
                // returns ln(param1) - log param1 to base e
                break :blk @log(parameter);
            } else if (std.mem.eql(u8, function_call.function_name, "log")) {
                // returns log param1 to base param2
                if (function_call.parameters.len != 2) return CalculationError.WrongParameters;

                const resultNumber = try evaluate(allocator, function_call.parameters[1]);
                // Block prevents a weird crash in "LLVM Emit Object" step (exit code 5)
                break :blk res_blk: {
                    if (parameter == 2) {
                        break :res_blk @log2(resultNumber);
                    } else if (parameter == 10) {
                        break :res_blk @log10(resultNumber);
                    } else {
                        break :res_blk @log(resultNumber) / @log(parameter);
                    }
                };
            } else if (std.mem.eql(u8, function_call.function_name, "pow")) {
                // returns param1^param2
                if (function_call.parameters.len != 2) return CalculationError.WrongParameters;
                const power = try evaluate(allocator, function_call.parameters[1]);
                break :blk std.math.pow(f32, parameter, power);
            } else if (std.mem.eql(u8, function_call.function_name, "sqrt")) {
                // returns square root of param1
                break :blk @sqrt(parameter);
            } else if (std.mem.eql(u8, function_call.function_name, "abs")) {
                // returns absolute value of param1
                break :blk std.math.absFloat(parameter);
            } else if (std.mem.eql(u8, function_call.function_name, "floor")) {
                // return floored value of param1
                break :blk std.math.floor(parameter);
            } else if (std.mem.eql(u8, function_call.function_name, "ceil")) {
                // returns ceiled value of param1
                break :blk std.math.ceil(parameter);
            } else {
                // user defined function
                const function_decl = allowed_blk: {
                    for (context.function_declarations.items) |decl| {
                        if (std.mem.eql(u8, decl.function_name, function_call.function_name))
                            break :allowed_blk &decl;
                    }
                    break :allowed_blk null;
                };
                if (function_decl == null) return CalculationError.UnknownFunction;
                if (function_call.parameters.len != function_decl.?.parameters.len) return CalculationError.WrongParameters;

                // Save previous size, to be able to later remove the declarations again
                var previousDefinedVariablesSize = context.variable_declarations.items.len;
                // Put parameters as variable declarations, since they are needed to evaluate the function equation
                for (function_call.parameters) |p, index| {
                    try context.variable_declarations.append(.{
                        .variable_name = function_decl.?.parameters[index],
                        .equation = p,
                    });
                }

                const function_equation = try allocator.alloc(AstNode, function_decl.?.equation.len);
                std.mem.copy(AstNode, function_equation, function_decl.?.equation);
                const result = try evaluate(allocator, function_equation);
                allocator.free(function_equation);

                // Remove previously added variables, since they are no longer defined
                while (context.variable_declarations.items.len > previousDefinedVariablesSize)
                    _ = context.variable_declarations.orderedRemove(context.variable_declarations.items.len - 1);

                break :blk result;
            }
        };

        equation[i].nodeType = .Operand;
        equation[i].value = .{ .operand = .{ .number = result } };
    }
}

fn convertUnits(allocator: Allocator, eq: []AstNode) CalculationError![]const AstNode {
    var equation = try allocator.dupe(AstNode, eq);

    var index: usize = 0;
    while (index < equation.len) {
        const operation = equation[index + 1];
        if (operation.nodeType != .Operator and operation.value.operation != .Conversion) {
            if (index + 4 >= equation.len) break;
            index += 2;
            continue;
        }

        const lhs = equation[index];
        const rhs = equation[index + 2];

        // Ensure that only one of both arguments is a unit
        if (lhs.nodeType != .Operand and rhs.nodeType != .Unit) return CalculationError.InvalidSyntax;

        const unit_function = try std.mem.concat(allocator, u8, &[_][]const u8{ lhs.value.operand.unit.?, "_", rhs.value.unit });
        std.debug.print("unit_function: {s}\n", .{unit_function});
        var result_value: f32 = undefined;

        inline for (comptime @typeInfo(units).Struct.decls) |decl| {
            std.debug.print("decl name: {s}", .{decl.name});
            if (std.mem.eql(u8, decl.name, unit_function)) {
                std.debug.print("found func\n", .{});
                result_value = callUnitFunction(@field(units, decl.name), .{lhs.value.operand.number});
                break;
            }
        }

        std.debug.print("result_value: {d}", .{result_value});

        // Set the current operands value to the result and change the unit to rhs' unit
        equation[index].value.operand.number = result_value;
        equation[index].value.operand.unit = try allocator.dupe(u8, rhs.value.unit);
        // Remove the next operator and operand
        equation = try std.mem.concat(allocator, AstNode, &[_][]const AstNode{ equation[0 .. index + 1], equation[index + 3 ..] });

        if (index + 2 >= equation.len) break;
        // Continue at the same element. This way, if there is another multiplication after this one,
        // we can just keep reducing the array until we're at the end or have only one value left
    }

    return equation;
}

fn callUnitFunction(function: anytype, args: anytype) type {
    return @call(.{}, function, args);
}

fn evaluatePointCalculations(allocator: Allocator, eq: []const AstNode) CalculationError![]const AstNode {
    var equation = try allocator.dupe(AstNode, eq);

    var index: usize = 0;
    while (index < equation.len) {
        try validateCalculationPair(equation, index);

        const operator = equation[index + 1].value.operation;

        switch (operator) {
            .Multiplication, .Division => {
                const lhs = equation[index].value.operand.number;
                const rhs = equation[index + 2].value.operand.number;

                const result: f32 = switch (operator) {
                    .Multiplication => lhs * rhs,
                    .Division => lhs / rhs, // TODO: Support floats
                    // This should never occur!!
                    else => return CalculationError.InvalidOperand,
                };

                // Set the current operands value to the result
                equation[index].value.operand.number = result;
                // Remove the next operator and operand
                equation = try std.mem.concat(allocator, AstNode, &[_][]const AstNode{ equation[0 .. index + 1], equation[index + 3 ..] });

                if (index + 2 >= equation.len) break;
                // Continue at the same element. This way, if there is another multiplication after this one,
                // we can just keep reducing the array until we're at the end or have only one value left
            },
            else => {
                // Check if there is another calculation pair
                if (index + 4 >= equation.len) break;
                index += 2;
            },
        }
    }

    return equation;
}

/// Returns whether a calculation can be done, according to units
fn canCalculate(lhs: AstNode, rhs: AstNode) bool {
    return (lhs.value.operand.unit == null or rhs.value.operand.unit == null) or std.mem.eql(u8, lhs.value.operand.unit.?, rhs.value.operand.unit.?);
}

fn validateCalculationPair(equation: []const AstNode, index: usize) CalculationError!void {
    if (equation[index].nodeType != .Operand) return CalculationError.ExpectedOperand;
    if (equation[index + 1].nodeType != .Operator) return CalculationError.ExpectedOperation;
    if (equation[index + 2].nodeType != .Operand) return CalculationError.ExpectedOperand;
}
