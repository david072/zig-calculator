const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const ast = @import("./ast.zig");

const VariableDeclaration = struct {
    variable_name: []const u8,
    equation: []ast.AstNode,
};

var allocator: Allocator = undefined;

pub var function_declarations: ArrayList(ast.FunctionDeclaration) = undefined;
pub var variable_declarations: ArrayList(VariableDeclaration) = undefined;

pub fn init(alloc: Allocator) void {
    allocator = alloc;
    function_declarations = ArrayList(ast.FunctionDeclaration).init(alloc);
    variable_declarations = ArrayList(VariableDeclaration).init(alloc);
}

pub fn deinit() void {
    for (function_declarations.items) |decl| decl.free(allocator);
    function_declarations.deinit();

    for (variable_declarations.items) |_, i| freeVariableDeclaration(i);
    variable_declarations.deinit();
}

pub fn freeVariableDeclaration(index: usize) void {
    allocator.free(variable_declarations.items[index].variable_name);

    for (variable_declarations.items[index].equation) |_, i|
        variable_declarations.items[index].equation[i].free(allocator);
    allocator.free(variable_declarations.items[index].equation);
}

/// Returns wheter `variable_name` is a "standard" variable (e, pi, phi)
pub fn isStandardVariable(variable_name: []const u8) bool {
    return sEql(variable_name, "e") or
        sEql(variable_name, "pi") or
        sEql(variable_name, "phi");
}

/// Returns the appropriate variable for:
/// - e
/// - pi
/// - phi
/// Otherwise null, indicating that a user defined variable is meant
pub fn resolveStandardVariable(variable_name: []const u8) ?f32 {
    if (sEql(variable_name, "e")) {
        return std.math.e;
    } else if (sEql(variable_name, "pi")) {
        return std.math.pi;
    } else if (sEql(variable_name, "phi")) {
        return std.math.phi;
    } else return null;
}

/// Resolves a user defined variable from `variable_declarations`
pub fn getVariable(variable_name: []const u8) ?*const VariableDeclaration {
    for (variable_declarations.items) |defined_variable| {
        if (sEql(variable_name, defined_variable.variable_name))
            return &defined_variable;
    }
    return null;
}

/// Checks if two slices of type `u8` are equal
fn sEql(lhs: []const u8, rhs: []const u8) bool {
    return std.mem.eql(u8, lhs, rhs);
}
