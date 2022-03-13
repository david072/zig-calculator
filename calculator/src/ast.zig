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
};

pub const FunctionCall = struct {
    function_name: []const u8,
    parameters: [][]AstNode,
};

pub const FunctionDeclaration = struct {
    function_name: []const u8,
    parameters: []const []const u8,
    equation: []AstNode,
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
