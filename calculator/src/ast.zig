const Allocator = @import("std").mem.Allocator;

pub const AstNode = struct {
    nodeType: AstNodeType,
    value: union {
        children: []AstNode,
        function_call: FunctionCall,
        nothing: u1,
        number: f32,
        variable_name: []const u8,
        operation: Operation,
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
            .Separator, .Operand, .Operator => {},
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
};

pub const Operation = enum {
    Addition,
    Subtraction,
    Multiplication,
    Division,
};
