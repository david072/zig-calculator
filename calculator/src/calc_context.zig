const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const ast = @import("astgen/ast.zig");
const VariableDeclaration = ast.VariableDeclaration;

var arena: std.heap.ArenaAllocator = undefined;

pub var function_declarations: ArrayList(ast.FunctionDeclaration) = undefined;
pub var variable_declarations: ArrayList(VariableDeclaration) = undefined;

pub fn init(allocator: Allocator) void {
    arena = std.heap.ArenaAllocator.init(allocator);
    function_declarations = ArrayList(ast.FunctionDeclaration).init(arena.allocator());
    variable_declarations = ArrayList(VariableDeclaration).init(arena.allocator());
}

pub fn lastingAllocator() Allocator {
    return arena.allocator();
}

pub fn deinit() void {
    arena.deinit();
}

pub fn getFunctionDeclarationIndex(name: []const u8) ?usize {
    for (function_declarations.items) |*decl, i|
        if (sEql(decl.function_name, name)) return i;

    return null;
}

pub fn getVariableDeclarationIndex(name: []const u8) ?usize {
    for (variable_declarations.items) |*decl, i|
        if (sEql(decl.variable_name, name)) return i;

    return null;
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
pub fn resolveStandardVariable(variable_name: []const u8) ?f64 {
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
