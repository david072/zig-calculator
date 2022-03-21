const Allocator = @import("std").mem.Allocator;

pub const AstNode = struct {
    nodeType: AstNodeType,
    value: union {
        children: []AstNode,
        function_call: FunctionCall,
        nothing: u1,
        operand: struct {
            number: f32,
            unit: ?[]const u8 = null,
        },
        variable_name: []const u8,
        operation: Operation,
        unit: []const u8, // Target unit for conversions
    },

    pub fn deepDupe(self: *const AstNode, allocator: Allocator) error{OutOfMemory}!AstNode {
        switch (self.nodeType) {
            .Group => {
                return AstNode{
                    .nodeType = self.nodeType,
                    .value = .{ .children = try deepDupeNodeList(&self.value.children, allocator) },
                };
            },
            .FunctionCall => {
                return AstNode{
                    .nodeType = self.nodeType,
                    .value = .{ .function_call = try self.value.function_call.deepDupe(allocator) },
                };
            },
            .Operand => {
                if (self.value.operand.unit == null) return self.*;

                return AstNode{
                    .nodeType = self.nodeType,
                    .value = .{
                        .operand = .{
                            .number = self.value.operand.number,
                            .unit = try allocator.dupe(u8, self.value.operand.unit.?),
                        },
                    },
                };
            },
            .VariableReference => {
                return AstNode{
                    .nodeType = self.nodeType,
                    .value = .{ .variable_name = try allocator.dupe(u8, self.value.variable_name) },
                };
            },
            .Unit => {
                return AstNode{
                    .nodeType = self.nodeType,
                    .value = .{ .unit = try allocator.dupe(u8, self.value.unit) },
                };
            },
            else => return self.*,
        }
    }

    fn deepDupeNodeList(list: *const []const AstNode, allocator: Allocator) error{OutOfMemory}![]AstNode {
        var result = try allocator.alloc(AstNode, list.len);
        for (list.*) |*item, i|
            result[i] = try item.deepDupe(allocator);
        return result;
    }
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
};

pub const AstNodeType = enum {
    Group,
    FunctionCall,
    Separator,
    Operand,
    VariableReference,
    Operator,
    Unit,
};

pub const Operation = enum {
    Addition,
    Subtraction,
    Multiplication,
    Division,
    Conversion,
};
