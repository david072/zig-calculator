const std = @import("std");
const Allocator = std.mem.Allocator;

const units = @import("../units.zig");

pub const AstNodeModifier = enum { None, Factorial, DoubleFactorial, Percent };
pub const Sign = enum { Positive, Negative };

pub const AstNode = struct {
    nodeType: AstNodeType,
    value: union {
        children: []AstNode,
        function_call: FunctionCall,
        nothing: void,
        operand: Operand,
        variable_name: []const u8,
        operation: Operation,
        unit: []const u8, // Target unit for conversions
        boolean: bool,
    },
    modifier: AstNodeModifier = .None,
    /// "temporary" variable used to store the sign of non-numbers (groups, ...).
    /// After a calculation is done, the number will contain the sign.
    sign: Sign = .Positive, 

    pub fn deepDupe(self: *const AstNode, allocator: Allocator) error{OutOfMemory}!AstNode {
        return AstNode{
            .nodeType = self.nodeType,
            .value = switch (self.nodeType) {
                .Group => .{ .children = try deepDupeNodeList(&self.value.children, allocator) },
                .FunctionCall => .{ .function_call = try self.value.function_call.deepDupe(allocator) },
                .Operand => .{
                    .operand = Operand{
                        .number = self.getNumber(),
                        .unit = if (self.value.operand.unit == null) null else try allocator.dupe(u8, self.value.operand.unit.?),
                    },
                },
                .VariableReference => .{ .variable_name = try allocator.dupe(u8, self.value.variable_name) },
                .Unit => .{ .unit = try allocator.dupe(u8, self.value.unit) },
                else => self.value,
            },
        };
    }

    fn deepDupeNodeList(list: *const []const AstNode, allocator: Allocator) error{OutOfMemory}![]AstNode {
        var result = try allocator.alloc(AstNode, list.len);
        for (list.*) |*item, i|
            result[i] = try item.deepDupe(allocator);
        return result;
    }

    /// Recursively frees all allocated memory inside this struct
    pub fn free(self: *const AstNode, allocator: Allocator) void {
        switch (self.nodeType) {
            .Group => for (self.value.children) |child| child.free(allocator),
            .FunctionCall => {
                allocator.free(self.value.function_call.function_name);
                for (self.value.function_call.parameters) |parameter| {
                    for (parameter) |p| p.free(allocator);
                    allocator.free(parameter);
                }
                allocator.free(self.value.function_call.parameters);
            },
            .VariableReference => allocator.free(self.value.variable_name),
            .Operand => {
                if (self.value.operand.unit != null)
                    allocator.free(self.value.operand.unit.?);
            },
            .Unit => allocator.free(self.value.unit),
            .EqualSign, .Operator, .Boolean => {},
        }
    }

    inline fn getNumber(self: *const AstNode) f64 {
        if (self.sign == .Negative) return self.value.operand.number * -1;
        return self.value.operand.number;
    }

    /// Returns `.value.operand.number` with the modifiers applied
    /// Assumes that this type is `.Operand`. Otherwise, `unreachable` is reached.
    pub fn getNumberValue(self: *const AstNode) error{InvalidNumber}!f64 {
        if (self.nodeType != .Operand) unreachable;

        return switch (self.modifier) {
            .None => self.getNumber(),
            .Factorial => {
                if (self.getNumber() < 0) {
                    return error.InvalidNumber;
                } else if (self.getNumber() == 0) return 0;

                var i: f64 = 1;
                var result: f64 = 1;
                while (i <= self.getNumber()) : (i += 1)
                    result *= i;

                return result;
            },
            .DoubleFactorial => {
                if (self.getNumber() < 0) {
                    return error.InvalidNumber;
                } else if (self.getNumber() == 0) return 0;

                var i: f64 = if (@mod(self.getNumber(), 2) == 0) 2 else 1;
                var result: f64 = 1;
                while (i <= self.getNumber()) : (i += 2)
                    result *= i;

                return result;
            },
            .Percent => self.getNumber() / 100,
        };
    }

    /// Modifies self's value using `operation` and `other` (rhs).
    /// Returns `error.InvalidParameters` if the parameters didn't match the pattern:
    /// - self: `nodeType = .Operand`
    /// - operation: `nodeType == .Operation`
    /// - other: `nodeType == .Operand` OR for conversions `nodeType == .Unit`
    pub fn apply(self: *AstNode, allocator: std.mem.Allocator, operation: *const AstNode, other: *const AstNode) error{ InvalidParameters, InvalidNumber, InvalidSyntax, UnknownConversion, OutOfMemory }!void {
        if (self.nodeType != .Operand or operation.nodeType != .Operator) return error.InvalidParameters;
        defer other.free(allocator);

        if (operation.value.operation == .Conversion) {
            if (other.nodeType != .Unit) return error.InvalidSyntax;
            // Convert units
            if (self.value.operand.unit == null) {
                self.value.operand.unit = try allocator.dupe(u8, other.value.unit);
                return;
            }
            self.value.operand.number = units.convert(self.getNumber(), self.value.operand.unit.?, other.value.unit) orelse return error.UnknownConversion;
            return;
        } else if (operation.value.operation == .Of) {
            if (self.modifier != .Percent or other.nodeType != .Operand) return error.InvalidSyntax;
            self.value.operand.number = (try self.getNumberValue()) * other.getNumber();
            if (other.value.operand.unit) |*unit|
                self.value.operand.unit = try allocator.dupe(u8, unit.*);
            self.modifier = .None;
            return;
        }

        if (other.nodeType != .Operand) return error.InvalidParameters;

        var rhs = try other.getNumberValue();
        var new_value = try self.getNumberValue();

        if (self.value.operand.unit != null and other.value.operand.unit != null) {
            if (!std.mem.eql(u8, self.value.operand.unit.?, other.value.operand.unit.?)) {
                // Convert rhs' value to our unit
                rhs = units.convert(rhs, other.value.operand.unit.?, self.value.operand.unit.?) orelse return error.UnknownConversion;
            }
        } else if (other.value.operand.unit != null) {
            // Carry rhs' unit over to lhs
            self.value.operand.unit = try allocator.dupe(u8, other.value.operand.unit.?);
        }

        switch (operation.value.operation) {
            .Addition => new_value += rhs,
            .Subtraction => new_value -= rhs,
            .Multiplication => new_value *= rhs,
            .Division => new_value /= rhs,
            .Conversion, .Of => unreachable, // Handled above
            .Power => new_value = std.math.pow(f64, new_value, rhs),
            .PowerOfTen => new_value *= std.math.pow(f64, 10, rhs),
            .BitwiseAnd => new_value = @intToFloat(f64, @floatToInt(i64, new_value) & @floatToInt(i64, rhs)),
            .BitwiseOr => new_value = @intToFloat(f64, @floatToInt(i64, new_value) | @floatToInt(i64, rhs)),
            .BitShiftRight => new_value = @intToFloat(f64, @floatToInt(i64, new_value) >> @floatToInt(u6, rhs)),
            .BitShiftLeft => new_value = @intToFloat(f64, @floatToInt(i64, new_value) << @floatToInt(u6, rhs)),
            .Xor => new_value = @intToFloat(f64, @floatToInt(i64, new_value) ^ @floatToInt(u6, rhs)),
        }

        self.value.operand.number = new_value;
        self.modifier = .None;
        self.sign = .Positive; // The number will now contain the correct sign.
    }
};

pub const Operand = struct {
    number: f64,
    unit: ?[]const u8 = null,
};

pub const FunctionCall = struct {
    function_name: []const u8,
    parameters: [][]AstNode,

    pub fn deepDupe(self: *const FunctionCall, allocator: Allocator) error{OutOfMemory}!FunctionCall {
        const function_name = try allocator.dupe(u8, self.function_name);

        const parameters = try allocator.alloc([]AstNode, self.parameters.len);
        for (self.parameters) |*param_list, i| {
            parameters[i] = try allocator.alloc(AstNode, param_list.len);
            for (param_list.*) |*param, j| {
                parameters[i][j] = try param.deepDupe(allocator);
            }
        }

        return FunctionCall{
            .function_name = function_name,
            .parameters = parameters,
        };
    }
};

pub const VariableDeclaration = struct {
    variable_name: []const u8,
    equation: []AstNode,

    pub fn free(self: *const VariableDeclaration, allocator: Allocator) void {
        allocator.free(self.variable_name);
        for (self.equation) |*node| node.free(allocator);
        allocator.free(self.equation);
    }
};

pub const FunctionDeclaration = struct {
    function_name: []const u8,
    parameters: []const []const u8,
    equation: []AstNode,

    pub fn deepDupeEquation(self: *const FunctionDeclaration, allocator: Allocator) error{OutOfMemory}![]AstNode {
        const result = try allocator.alloc(AstNode, self.equation.len);
        for (self.equation) |*node, i|
            result[i] = try node.deepDupe(allocator);

        return result;
    }

    pub fn free(self: *const FunctionDeclaration, allocator: Allocator) void {
        allocator.free(self.function_name);

        for (self.parameters) |*param| allocator.free(param.*);
        allocator.free(self.parameters);

        for (self.equation) |*node| node.free(allocator);
        allocator.free(self.equation);
    }
};

pub const AstNodeType = enum {
    Group,
    FunctionCall,
    Operand,
    VariableReference,
    Operator,
    Unit,
    EqualSign,
    Boolean,
};

pub const Operation = enum {
    Addition,
    Subtraction,
    Multiplication,
    Division,
    Conversion,
    Of,
    Power,
    PowerOfTen,
    BitwiseAnd,
    BitwiseOr,
    BitShiftRight,
    BitShiftLeft,
    Xor,
};
