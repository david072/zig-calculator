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
            .Separator, .Operator => {},
        }
    }
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
