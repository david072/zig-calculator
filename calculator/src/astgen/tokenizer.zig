const std = @import("std");

pub const TokenType = enum {
    whitespace,
    number,
    in,
    @"+",
    @"-",
    @"*",
    @"/",
    @"(",
    @")",
    declaration,
    undeclaration,
    identifier,
    separator,

    pub fn isOperand(self: *const TokenType) bool {
        return self.* == .@"+" or
            self.* == .@"-" or
            self.* == .@"*" or
            self.* == .@"/";
    }
};

pub const keywords = [_][]const u8{"in"};

pub const Token = struct {
    type: TokenType,
    text: []const u8,
};

pub const Tokenizer = struct {
    const Self = @This();

    pub const Result = union(enum) {
        token: Token,
        end_of_file: void,
        invalid_character_index: usize,
    };

    source: []const u8,
    index: usize = 0,

    pub fn init(source: []const u8) Self {
        return Self{ .source = source };
    }

    pub fn next(self: *Self) Result {
        if (self.index >= self.source.len) return .end_of_file;

        const start = self.index;
        if (self.nextInternal()) |token_type| {
            const end = self.index;
            std.debug.assert(end > start);

            var token = Token{
                .type = token_type,
                .text = self.source[start..end],
            };

            if (token_type == .identifier) {
                inline for (keywords) |kwd| {
                    if (std.mem.eql(u8, token.text, kwd)) {
                        token.type = @field(TokenType, kwd);
                        break;
                    }
                }
            }

            return Result{ .token = token };
        } else {
            return Result{ .invalid_character_index = self.index };
        }
    }

    const Predicate = fn (u8) bool;

    fn accept(self: *Self, predicate: Predicate) bool {
        if (self.index >= self.source.len) return false;

        const c = self.source[self.index];
        if (predicate(c)) {
            self.index += 1;
            return true;
        } else {
            return false;
        }
    }

    fn anyOf(comptime chars: []const u8) Predicate {
        return struct {
            fn pred(c: u8) bool {
                return inline for (chars) |o| {
                    if (c == o)
                        break true;
                } else false;
            }
        }.pred;
    }

    fn noneOf(comptime chars: []const u8) Predicate {
        return struct {
            fn pred(c: u8) bool {
                return inline for (chars) |o| {
                    if (c == o)
                        break false;
                } else true;
            }
        }.pred;
    }

    const invalid_char_class = noneOf(" \r\n\tABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789+-*/%={}()[]<>\"\'.,;!");
    const whitespace_class = anyOf(" \r\n\t");
    /// unit / function / variable name (or other invalid word)
    const identifier_class = anyOf("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789");
    const digit_class = anyOf("0123456789.");

    fn nextInternal(self: *Self) ?TokenType {
        // Fast-forward through whitespace
        if (self.accept(whitespace_class)) {
            while (self.accept(whitespace_class)) {}
            return .whitespace;
        }

        const character = self.source[self.index];
        self.index += 1;
        switch (character) {
            '0'...'9' => {
                while (self.accept(digit_class)) {}
                return .number;
            },
            'a'...'z', 'A'...'Z' => {
                while (self.accept(identifier_class)) {}
                return .identifier;
            },
            '+' => return .@"+",
            '-' => return .@"-",
            '*' => return .@"*",
            '/' => return .@"/",
            '(' => return .@"(",
            ')' => return .@")",
            ',' => return .separator,
            else => return null,
        }
    }
};

/// Turns `source` into a slice of tokens.
/// The result must be freed by the caller.
pub const TokenizerError = error{InvalidCharacter} || std.mem.Allocator.Error;
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) TokenizerError![]const Token {
    var tokens = std.ArrayList(Token).init(allocator);
    var tokenizer = Tokenizer{ .source = source };

    while (true) {
        switch (tokenizer.next()) {
            .end_of_file => return tokens.toOwnedSlice(),
            .token => |token| try tokens.append(token),
            .invalid_character_index => {
                // TODO: Use the index
                return error.InvalidCharacter;
            },
        }
    }
}
