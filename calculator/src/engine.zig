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
    UnknownConversion,
    UnexpectedUnit,

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

pub fn evaluate(allocator: Allocator, tree: []AstNode) CalculationError!AstNode {
    var currentNestingLevel: usize = 0;
    var deepestNestingLevel: usize = 0;
    var deepestNestedGroup: ?*AstNode = findDeepestNestedGroup(tree, &currentNestingLevel, &deepestNestingLevel);

    while (deepestNestedGroup != null) {
        const groupResult = try evaluateEquation(allocator, deepestNestedGroup.?.value.children);

        deepestNestedGroup.?.* = groupResult;

        currentNestingLevel = 0;
        deepestNestingLevel = 0;
        deepestNestedGroup = findDeepestNestedGroup(tree, &currentNestingLevel, &deepestNestingLevel);
    }

    return evaluateEquation(allocator, tree);
}

/// Calls `evaluate`, ensuring the result does not have a unit
/// If it has one, it will return `CalculationError.UnexpectedUnit`
fn evaluateNumber(allocator: Allocator, tree: *[]AstNode) CalculationError!f32 {
    const node = try evaluate(allocator, tree.*);
    if (node.value.operand.unit != null) return CalculationError.UnexpectedUnit;
    return node.value.operand.number;
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

fn evaluateEquation(allocator: Allocator, originalEquation: []AstNode) CalculationError!AstNode {
    try expandVariables(allocator, originalEquation);
    try evaluateFunctions(allocator, originalEquation);

    if (originalEquation.len == 1 and originalEquation[0].nodeType == .Operand) {
        return originalEquation[0];
    } else if (originalEquation.len < 3) return CalculationError.NotEnoughNodes;

    var equation = try allocator.dupe(AstNode, originalEquation);

    try convertUnits(allocator, &equation);
    try evaluatePointCalculations(allocator, &equation);

    if (equation.len == 1) {
        if (equation[0].nodeType != .Operand) return CalculationError.ExpectedOperand;
        return equation[0];
    }

    var index: usize = 0;
    while (index < equation.len) {
        try validateCalculationPair(equation, index);

        const lhs = &equation[index];
        const rhs = &equation[index + 2];

        try convertCalculationPairUnits(allocator, lhs, rhs);

        switch (equation[index + 1].value.operation) {
            .Addition => lhs.value.operand.number += rhs.value.operand.number,
            .Subtraction => lhs.value.operand.number -= rhs.value.operand.number,
            else => continue,
        }

        equation = try std.mem.concat(allocator, AstNode, &[_][]const AstNode{ equation[0 .. index + 1], equation[index + 3 ..] });

        if (index + 2 >= equation.len) break;
    }

    return equation[0];
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

        tree[i] = try evaluate(allocator, defined_variable.equation);
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
        const parameter = try evaluateNumber(allocator, &function_call.parameters[0]);

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

                const resultNumber = try evaluateNumber(allocator, &function_call.parameters[0]);

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
                const power = try evaluateNumber(allocator, &function_call.parameters[1]);
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

                // FIXME: Do we really need to deep dupe here?
                // TODO: How can functions use units as parameters and return units?
                var function_equation = try function_decl.?.deepDupeEquation(allocator);
                const result = try evaluateNumber(allocator, &function_equation);
                // function_equation too complex to free here. We just leave it until the parent
                // arena allocator is destroyed, since we technically don't have to free it

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

fn convertUnits(allocator: Allocator, equation: *[]AstNode) CalculationError!void {
    var index: usize = 0;
    while (index < equation.len) {
        const operation = equation.*[index + 1];
        if (operation.nodeType != .Operator and operation.value.operation != .Conversion) {
            if (index + 4 >= equation.len) break;
            index += 2;
            continue;
        }

        const lhs = equation.*[index];
        const rhs = equation.*[index + 2];

        // Validate syntax
        if ((lhs.nodeType != .Operand or rhs.nodeType != .Unit) or lhs.value.operand.unit == null) {
            if (operation.value.operation == .Conversion) return CalculationError.InvalidSyntax;
            if (index + 4 >= equation.len) break;
            index += 2;
            continue;
        }

        // Convert lhs' value from lhs' unit to rhs' unit
        var result_value = units.convert(lhs.value.operand.number, lhs.value.operand.unit.?, rhs.value.unit) orelse return CalculationError.UnknownConversion;

        // Set the current operands value to the result and change the unit to rhs' unit
        equation.*[index].value.operand.number = result_value;
        equation.*[index].value.operand.unit = try allocator.dupe(u8, rhs.value.unit);
        // Remove the next operator and operand
        equation.* = try std.mem.concat(allocator, AstNode, &[_][]const AstNode{ equation.*[0 .. index + 1], equation.*[index + 3 ..] });

        if (index + 2 >= equation.len) break;
        // Continue at the same element. This way, if there is another multiplication after this one,
        // we can just keep reducing the array until we're at the end or have only one value left
    }
}

fn evaluatePointCalculations(allocator: Allocator, equation: *[]AstNode) CalculationError!void {
    if (equation.len < 3) return;

    var index: usize = 0;
    while (index < equation.len) {
        try validateCalculationPair(equation.*, index);

        const operator = equation.*[index + 1].value.operation;

        switch (operator) {
            .Multiplication, .Division => {
                const lhs = &equation.*[index];
                const rhs = &equation.*[index + 2];

                try convertCalculationPairUnits(allocator, lhs, rhs);

                switch (operator) {
                    .Multiplication => lhs.value.operand.number *= rhs.value.operand.number,
                    .Division => lhs.value.operand.number /= rhs.value.operand.number,
                    // This should never occur!!
                    else => return CalculationError.InvalidOperand,
                }

                // Remove the next operator and operand
                equation.* = try std.mem.concat(allocator, AstNode, &[_][]const AstNode{ equation.*[0 .. index + 1], equation.*[index + 3 ..] });

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
}

/// Converts units in a calculation pair, preferring lhs' unit.
/// Examples:
/// - `4m + 3ft` -> rhs' value will be converted from rhs' unit to lhs' unit
/// - `4 + 3ft` -> rhs' unit is duped and carried over to lhs
/// - `4m + 3`, `4 + 3` and `4m + 3m` -> nothing happens
fn convertCalculationPairUnits(allocator: Allocator, lhs: *AstNode, rhs: *AstNode) CalculationError!void {
    if (lhs.value.operand.unit != null and rhs.value.operand.unit != null) {
        if (!std.mem.eql(u8, lhs.value.operand.unit.?, rhs.value.operand.unit.?)) {
            // Convert rhs' value to lhs' unit
            rhs.value.operand.number = units.convert(rhs.value.operand.number, rhs.value.operand.unit.?, lhs.value.operand.unit.?) orelse return CalculationError.UnknownConversion;
        }
    } else if (rhs.value.operand.unit != null) {
        // Carry rhs' unit over to lhs
        lhs.value.operand.unit = try allocator.dupe(u8, rhs.value.operand.unit.?);
    }
}

fn validateCalculationPair(equation: []const AstNode, index: usize) CalculationError!void {
    if (equation[index].nodeType != .Operand) return CalculationError.ExpectedOperand;
    if (equation[index + 1].nodeType != .Operator) return CalculationError.ExpectedOperation;
    if (equation[index + 2].nodeType != .Operand) return CalculationError.ExpectedOperand;
}
