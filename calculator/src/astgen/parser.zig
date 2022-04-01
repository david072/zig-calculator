const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const calc_context = @import("../calc_context.zig");
const units = @import("../units.zig");

const ast = @import("ast.zig");
const AstNode = ast.AstNode;

pub const ParsingError = error{
    UnexpectedValue,
    MissingBracket,
    UnknownUnit,
    UnknownVariable,
    UnexpectedModifier,
    Overflow,
} || std.fmt.ParseFloatError || Allocator.Error;

pub const Parser = struct {
    const Self = @This();
    // start is the starting value and should not be used otherwise!
    const CategorizedTokenType = enum { numberLiteral, operator, other, start };

    allocator: Allocator,
    tokens: []const tokenizer.Token,
    result: ArrayList(AstNode),

    current_identifier: ?*const tokenizer.Token = null,
    last_type: CategorizedTokenType = .start,

    allowed_variables: []const []const u8 = &[_][]const u8{},

    pub fn init(allocator: Allocator, tokens: []const tokenizer.Token) Self {
        return Self{
            .allocator = allocator,
            .tokens = tokens,
            .result = ArrayList(AstNode).init(allocator),
        };
    }

    pub fn parseInternal(self: *Self) ParsingError![]AstNode {
        var i: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const token = &self.tokens[i];
            switch (token.type) {
                .whitespace => continue,
                .@"(" => {
                    self.last_type = .other;
                    if (self.current_identifier != null) {
                        try self.parseFunctionCall(&i);
                        continue;
                    }

                    try self.parseGroupFrom(&i);
                },
                .@")" => return ParsingError.MissingBracket,
                .identifier => {
                    defer self.last_type = .other;

                    if (self.last_type == .numberLiteral) {
                        if (!units.isUnit(token.text)) return ParsingError.UnknownUnit;
                        self.result.items[self.result.items.len - 1].value.operand.unit = token.text;
                        continue;
                    } else if (self.last_type == .operator) {
                        const last_node = &self.result.items[self.result.items.len - 1];
                        if (last_node.nodeType == .Operator and last_node.value.operation == .Conversion) {
                            if (!units.isUnit(token.text)) return ParsingError.UnknownUnit;
                            try self.result.append(.{
                                .nodeType = .Unit,
                                .value = .{ .unit = token.text },
                            });
                            continue;
                        }
                    }

                    // Identifier is either variable or function call.
                    // We need to continue however, to find out which one was meant.
                    self.current_identifier = token;
                },
                .@"!" => try self.appendModifier(.Factorial),
                .@"!!" => try self.appendModifier(.DoubleFactorial),
                .@"%" => try self.appendModifier(.Percent),
                else => try self.parseAstNode(token),
            }
        }

        try self.appendVariableReference(true);
        return self.result.toOwnedSlice();
    }

    fn appendModifier(self: *Self, modifier: ast.AstNodeModifier) ParsingError!void {
        try self.appendVariableReference(true);
        if (self.result.items.len == 0) return ParsingError.UnexpectedModifier;

        self.result.items[self.result.items.len - 1].modifier = modifier;
    }

    /// Appends a variable reference node to the result, if there is one
    fn appendVariableReference(self: *Self, skip_validation: bool) ParsingError!void {
        if (self.current_identifier == null) return;
        if (!skip_validation)
            if (self.last_type != .operator and self.last_type != .start) return ParsingError.UnexpectedValue;

        const variable = self.current_identifier.?;

        // Check if variable is valid
        var_blk: {
            if (calc_context.isStandardVariable(variable.text)) break :var_blk;
            if (calc_context.getVariableDeclarationIndex(variable.text) != null) break :var_blk;

            for (self.allowed_variables) |*v|
                if (std.mem.eql(u8, variable.text, v.*)) break :var_blk;
            return ParsingError.UnknownVariable;
        }

        try self.result.append(.{
            .nodeType = .VariableReference,
            .value = .{ .variable_name = variable.text },
        });
        self.current_identifier = null;
    }

    fn parseFunctionCall(self: *Self, index: *usize) ParsingError!void {
        var parameters = try self.allocator.alloc([]AstNode, 1);
        var parameter_index: usize = 0;

        index.* += 1;
        var start_index = index.*;

        var nesting_level: u8 = 0;
        while (index.* < self.tokens.len) : (index.* += 1) {
            switch (self.tokens[index.*].type) {
                .separator => {
                    const parameter_tokens = self.tokens[start_index..index.*];
                    const nodes = try parseWithVariables(self.allocator, parameter_tokens, self.allowed_variables);
                    if (parameter_index >= parameters.len)
                        parameters = try self.allocator.realloc(parameters, parameters.len + 1);

                    parameters[parameter_index] = nodes;
                    parameter_index += 1;
                    start_index = index.* + 1;
                },
                .@"(" => nesting_level += 1,
                .@")" => {
                    if (nesting_level > 0) {
                        nesting_level -= 1;
                        continue;
                    }

                    const parameter_tokens = self.tokens[start_index..index.*];
                    const nodes = try parseWithVariables(self.allocator, parameter_tokens, self.allowed_variables);
                    if (parameter_index >= parameters.len)
                        parameters = try self.allocator.realloc(parameters, parameters.len + 1);

                    parameters[parameter_index] = nodes;
                    break;
                },
                else => continue,
            }
        }

        const function_call_node = AstNode{
            .nodeType = .FunctionCall,
            .value = .{
                .function_call = .{
                    .function_name = self.current_identifier.?.text,
                    .parameters = parameters,
                },
            },
        };
        self.current_identifier = null;
        try self.result.append(function_call_node);
    }

    fn parseGroupFrom(self: *Self, index: *usize) ParsingError!void {
        index.* += 1;

        var start_index = index.*;
        var end_index: ?usize = null;

        var nesting_level: u8 = 0;
        while (index.* < self.tokens.len) : (index.* += 1) {
            switch (self.tokens[index.*].type) {
                .@"(" => nesting_level += 1,
                .@")" => {
                    if (nesting_level > 0) {
                        nesting_level -= 1;
                        continue;
                    }

                    end_index = index.*;
                    break;
                },
                else => continue,
            }
        }

        if (end_index == null) return ParsingError.MissingBracket;

        const group_content = self.tokens[start_index..end_index.?];
        const nodes = try parseWithVariables(self.allocator, group_content, self.allowed_variables);
        const group_node = AstNode{
            .nodeType = .Group,
            .value = .{ .children = nodes },
        };

        try self.result.append(group_node);
    }

    fn parseAstNode(self: *Self, token: *const tokenizer.Token) ParsingError!void {
        if (self.last_type == categorizedTokenType(token.type)) return ParsingError.UnexpectedValue;
        self.last_type = categorizedTokenType(token.type);

        // Potentially add variable reference
        try self.appendVariableReference(false);
        try self.result.append(try astNodeFromToken(token));
    }

    fn categorizedTokenType(t: tokenizer.TokenType) CategorizedTokenType {
        if (t.isOperator()) return .operator;

        return switch (t) {
            .number => .numberLiteral,
            else => .other,
        };
    }

    fn astNodeFromToken(token: *const tokenizer.Token) !AstNode {
        if (token.type == .number) {
            var number: f64 = if (std.mem.startsWith(u8, token.text, "0x") or std.mem.startsWith(u8, token.text, "0b")) blk: {
                break :blk @intToFloat(f64, try std.fmt.parseInt(u64, token.text, 0));
            } else blk: {
                break :blk try std.fmt.parseFloat(f64, token.text);
            };

            return AstNode{
                .nodeType = .Operand,
                .value = .{
                    .operand = .{ .number = number },
                },
            };
        } else if (token.type == .@"=") {
            return AstNode{
                .nodeType = .EqualSign,
                .value = .{ .nothing = {} },
            };
        }

        return AstNode{
            .nodeType = .Operator,
            .value = .{
                .operation = switch (token.type) {
                    .@"+" => .Addition,
                    .@"-" => .Subtraction,
                    .@"*" => .Multiplication,
                    .@"/" => .Division,
                    .in => .Conversion,
                    .of => .Of,
                    .@"^" => .Power,
                    .e => .PowerOfTen,
                    .@"&" => .BitwiseAnd,
                    .@"|" => .BitwiseOr,
                    .@">>" => .BitShiftRight,
                    .@"<<" => .BitShiftLeft,
                    else => unreachable,
                },
            },
        };
    }
};

pub fn parse(allocator: Allocator, tokens: []const tokenizer.Token) ParsingError![]AstNode {
    var parser = Parser.init(allocator, tokens);
    return parser.parseInternal();
}

pub fn parseWithVariables(allocator: Allocator, tokens: []const tokenizer.Token, variables: []const []const u8) ParsingError![]AstNode {
    var parser = Parser.init(allocator, tokens);
    parser.allowed_variables = variables;
    return parser.parseInternal();
}

const DeclarationError = error{ MissingEqualSign, UnexpectedSeparator } || tokenizer.TokenizerError || ParsingError;

pub fn parseDeclaration(allocator: Allocator, input: []const u8) DeclarationError!void {
    const equal_sign_index = std.mem.indexOf(u8, input, "=") orelse return error.MissingEqualSign;
    const signature = try tokenizer.tokenize(allocator, input[0..equal_sign_index]);
    const equation = try tokenizer.tokenize(allocator, input[equal_sign_index + 1 ..]);

    const lasting_allocator = calc_context.lastingAllocator();

    var name: ?[]const u8 = null;
    var parameters = ArrayList([]const u8).init(lasting_allocator);

    var is_function_decl = false;
    var has_reached_end = false;
    var expecting_separator = false;
    for (signature) |*token| {
        switch (token.type) {
            .whitespace => continue,
            .@"(" => is_function_decl = true,
            .@")" => {
                if (!is_function_decl) return ParsingError.MissingBracket;
                has_reached_end = true;
            },
            .separator => {
                if (!expecting_separator) return error.UnexpectedSeparator;
                expecting_separator = false;
            },
            else => {
                if (has_reached_end) return ParsingError.UnexpectedValue;
                if (token.type != .identifier) return ParsingError.UnexpectedValue;

                if (name == null) {
                    name = token.text;
                    continue;
                } else if (!is_function_decl) return ParsingError.UnexpectedValue;

                try parameters.append(try lasting_allocator.dupe(u8, token.text));
                expecting_separator = true;
            },
        }
    }

    if (is_function_decl) {
        var old_index: ?usize = null;
        if (calc_context.getFunctionDeclarationIndex(name.?)) |i| old_index = i;

        const eq = try parseWithVariables(lasting_allocator, equation, parameters.items);
        try calc_context.function_declarations.append(.{
            .function_name = try lasting_allocator.dupe(u8, name.?),
            .parameters = parameters.toOwnedSlice(),
            .equation = eq,
        });

        if (old_index != null)
            _ = calc_context.function_declarations.swapRemove(old_index.?);
    } else {
        var old_index: ?usize = null;
        if (calc_context.getVariableDeclarationIndex(name.?)) |i| old_index = i;

        try calc_context.variable_declarations.append(.{
            .variable_name = try lasting_allocator.dupe(u8, name.?),
            .equation = try parse(lasting_allocator, equation),
        });

        if (old_index != null)
            _ = calc_context.variable_declarations.swapRemove(old_index.?);
    }
}

pub fn parseUnDeclaration(allocator: Allocator, input: []const u8) error{ UnexpectedCharacter, OutOfMemory }!void {
    var _name = ArrayList(u8).init(allocator);
    for (input) |char| {
        switch (char) {
            ' ', '\r', '\n' => continue,
            'a'...'z', 'A'...'Z' => try _name.append(char),
            else => return error.UnexpectedCharacter,
        }
    }

    const name = _name.toOwnedSlice();
    if (calc_context.getFunctionDeclarationIndex(name)) |i| {
        calc_context.function_declarations.items[i].free(calc_context.lastingAllocator());
        _ = calc_context.function_declarations.orderedRemove(i);
    } else if (calc_context.getVariableDeclarationIndex(name)) |i| {
        calc_context.variable_declarations.items[i].free(calc_context.lastingAllocator());
        _ = calc_context.variable_declarations.orderedRemove(i);
    }
}
