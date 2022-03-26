const std = @import("std");
const ArrayList = std.ArrayList;

const tokenizer = @import("tokenizer.zig");

const ast = @import("ast.zig");
const AstNode = ast.AstNode;

pub const ParsingError = error{
    UnexpectedValue,
    MissingBracket,
} || std.fmt.ParseFloatError || std.mem.Allocator.Error;

pub const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tokens: []const tokenizer.Token,
    result: ArrayList(AstNode),
    last_type: ?tokenizer.TokenType = null,

    current_identifier: ?*const tokenizer.Token = null,

    pub fn init(allocator: std.mem.Allocator, tokens: []const tokenizer.Token) Self {
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
                    if (self.current_identifier != null) {
                        try self.parseFunctionCall(&i);
                        continue;
                    }

                    try self.parseGroupFrom(&i);
                },
                .@")" => return ParsingError.MissingBracket,
                .identifier => {
                    if (self.last_type != null and self.last_type.? == .number) {
                        self.result.items[self.result.items.len - 1].value.operand.unit = token.text;
                        continue;
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
        if (self.last_type != null) {
            if (self.last_type == token.type) return ParsingError.UnexpectedValue;
        }

        // Handle variable reference
        if (self.current_identifier) |identifier| blk: {
            if (!token.type.isOperand()) break :blk;
            if (self.last_type != null and !self.last_type.?.isOperand()) break :blk;

            self.last_type = identifier.type;
            const node = AstNode{
                .nodeType = .VariableReference,
                .value = .{ .variable_name = identifier.text },
            };
            try self.result.append(node);
        }

        self.last_type = token.type;
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
            // TODO
            else => unreachable,
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []const tokenizer.Token) ParsingError!ArrayList(AstNode) {
    var parser = Parser.init(allocator, tokens);
    return parser.parseInternal();
}
