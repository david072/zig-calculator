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
} || std.fmt.ParseFloatError || Allocator.Error;

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    tokens: []const tokenizer.Token,
    result: ArrayList(AstNode),

    current_identifier: ?*const tokenizer.Token = null,
    previous_was_operand: bool = true,

    pub fn init(allocator: Allocator, tokens: []const tokenizer.Token) Self {
        return Self{
            .allocator = allocator,
            .tokens = tokens,
            .result = ArrayList(AstNode).init(allocator),
        };
    }

    pub fn parseInternal(self: *Self) ParsingError!ArrayList(AstNode) {
        var i: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const token = &self.tokens[i];
            switch (token.type) {
                .whitespace => continue,
                .@"(" => {
                    self.previous_was_operand = false;
                    if (self.current_identifier != null) {
                        try self.parseFunctionCall(&i);
                        continue;
                    }

                    try self.parseGroupFrom(&i);
                },
                .@")" => return ParsingError.MissingBracket,
                .identifier => {
                    if (!self.previous_was_operand) {
                        if (!units.isUnit(token.text)) return ParsingError.UnknownUnit;
                        self.result.items[self.result.items.len - 1].value.operand.unit = token.text;
                        continue;
                    } else {
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
                else => try self.parseAstNode(token),
            }
        }

        if (self.current_identifier != null) {
            const node = AstNode{
                .nodeType = .VariableReference,
                .value = .{ .variable_name = self.current_identifier.?.text },
            };
            try self.result.append(node);
        }

        return self.result;
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
                    const nodes = (try parse(self.allocator, parameter_tokens)).toOwnedSlice();
                    if (parameter_index >= parameters.len)
                        parameters = try self.allocator.realloc(parameters, parameters.len + 1);

                    parameters[parameter_index] = nodes;
                    parameter_index += 1;
                    start_index = index.* + 1;
                },
                .@")" => {
                    if (nesting_level > 0) {
                        nesting_level -= 1;
                        continue;
                    }

                    const parameter_tokens = self.tokens[start_index..index.*];
                    const nodes = (try parse(self.allocator, parameter_tokens)).toOwnedSlice();
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
        const nodes = (try parse(self.allocator, group_content)).toOwnedSlice();
        const group_node = AstNode{
            .nodeType = .Group,
            .value = .{ .children = nodes },
        };

        try self.result.append(group_node);
    }

    fn parseAstNode(self: *Self, token: *const tokenizer.Token) ParsingError!void {
        if (self.previous_was_operand == token.type.isOperand()) return ParsingError.UnexpectedValue;

        // Handle variable reference
        if (self.current_identifier) |identifier| blk: {
            if (!token.type.isOperand()) break :blk;
            if (!self.previous_was_operand) break :blk;

            self.previous_was_operand = false;
            const node = AstNode{
                .nodeType = .VariableReference,
                .value = .{ .variable_name = identifier.text },
            };
            try self.result.append(node);
            self.current_identifier = null;
        }

        self.previous_was_operand = token.type.isOperand();
        try self.result.append(try astNodeFromToken(token));
    }

    fn astNodeFromToken(token: *const tokenizer.Token) !AstNode {
        return switch (token.type) {
            .number => AstNode{
                .nodeType = .Operand,
                .value = .{
                    .operand = .{ .number = try std.fmt.parseFloat(f64, token.text) },
                },
            },
            .@"+" => AstNode{
                .nodeType = .Operator,
                .value = .{ .operation = .Addition },
            },
            .@"-" => AstNode{
                .nodeType = .Operator,
                .value = .{ .operation = .Subtraction },
            },
            .@"*" => AstNode{
                .nodeType = .Operator,
                .value = .{ .operation = .Multiplication },
            },
            .@"/" => AstNode{
                .nodeType = .Operator,
                .value = .{ .operation = .Division },
            },
            .in => AstNode{
                .nodeType = .Operator,
                .value = .{ .operation = .Conversion },
            },
            else => unreachable,
        };
    }
};

pub fn parse(allocator: Allocator, tokens: []const tokenizer.Token) ParsingError!ArrayList(AstNode) {
    var parser = Parser.init(allocator, tokens);
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

                try parameters.append(token.text);
                expecting_separator = true;
            },
        }
    }

    if (is_function_decl) {
        var old_index: ?usize = null;
        if (calc_context.getFunctionDeclarationIndex(name.?)) |i| old_index = i;

        try calc_context.function_declarations.append(.{
            .function_name = try lasting_allocator.dupe(u8, name.?),
            .parameters = parameters.toOwnedSlice(),
            .equation = (try parse(lasting_allocator, equation)).toOwnedSlice(),
        });

        if (old_index != null)
            _ = calc_context.function_declarations.swapRemove(old_index.?);
    } else {
        var old_index: ?usize = null;
        if (calc_context.getVariableDeclarationIndex(name.?)) |i| old_index = i;

        try calc_context.variable_declarations.append(.{
            .variable_name = try lasting_allocator.dupe(u8, name.?),
            .equation = (try parse(lasting_allocator, equation)).toOwnedSlice(),
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
