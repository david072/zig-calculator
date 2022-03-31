const std = @import("std");

pub const TokenType = enum {
    whitespace,
    number,
    in,
    e,
    @"+",
    @"-",
    @"*",
    @"/",
    @"(",
    @")",
    @"^",
    @"&",
    @"|",
    @">>",
    @"<<",
    @"!",
    @"%",
    declaration,
    undeclaration,
    identifier,
    separator,

    pub fn isOperator(self: TokenType) bool {
        return switch (self) {
            .@"+", .@"-", .@"*", .@"/", .in, .@"^", .e, .@"&", .@"|", .@">>", .@"<<" => true,
            else => false,
        };
    }
};

pub const keywords = [_][]const u8{ "in", "e" };

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
    last_token_type: ?TokenType = null,

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

            if (token_type == .identifier) blk: {
                if (std.mem.eql(u8, self.source[start..end], "in")) {
                    if (self.last_token_type != null and self.last_token_type.? == .whitespace)
                        token.type = TokenType.in;
                    break :blk;
                }

                inline for (keywords) |kwd| {
                    if (std.mem.eql(u8, token.text, kwd)) {
                        token.type = @field(TokenType, kwd);
                        break;
                    }
                }
            }

            self.last_token_type = token.type;
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
    const letter_class = anyOf("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
    const digit_class = anyOf("0123456789.");
    const hexadecimal_class = anyOf("0123456789abcdefABCDEF");
    const binary_class = anyOf("01");

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
                if (self.accept(anyOf("x"))) {
                    while (self.accept(hexadecimal_class)) {}
                    return .number;
                } else if (self.accept(anyOf("b"))) {
                    while (self.accept(binary_class)) {}
                    return .number;
                }

                while (self.accept(digit_class)) {}
                return .number;
            },
            'a'...'z', 'A'...'Z' => {
                if (character == 'e' or character == 'E') {
                    if (!self.accept(letter_class))
                        return .e;
                }

                while (self.accept(identifier_class)) {}
                return .identifier;
            },
            '+' => {
                if (self.accept(digit_class)) {
                    while (self.accept(digit_class)) {}
                    return .number;
                }
                return .@"+";
            },
            '-' => {
                if (self.accept(digit_class)) {
                    while (self.accept(digit_class)) {}
                    return .number;
                }
                return .@"-";
            },
            '*' => return .@"*",
            '/' => return .@"/",
            '(' => return .@"(",
            ')' => return .@")",
            '^' => return .@"^",
            '&' => return .@"&",
            '|' => return .@"|",
            '>' => {
                if (!self.accept(anyOf(">"))) return null;
                return .@">>";
            },
            '<' => {
                if (!self.accept(anyOf("<"))) return null;
                return .@"<<";
            },
            ',' => return .separator,
            '!' => return .@"!",
            '%' => return .@"%",
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
