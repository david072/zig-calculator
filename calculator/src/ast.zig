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
};

pub const FunctionCall = struct {
    function_name: []const u8,
    parameters: [][]AstNode,
};

pub const FunctionDeclaration = struct {
    function_name: []const u8,
    parameters: []const []const u8,
    equation: []AstNode,

    pub fn free(self: *const FunctionDeclaration, allocator: Allocator) void {
        allocator.free(self.function_name);
        for (self.parameters) |param| allocator.free(param);
        for (self.equation) |node| node.free(allocator);
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
