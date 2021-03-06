const std = @import("std");

const calculator = @import("calculator");

var evaluate_depth: ?calculator.EvaluateDepth = null;
var verbosity: ?calculator.Verbosity = null;

const exitInput = "exit";

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [100]u8 = undefined;

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    try parseArgs(gpa.allocator());

    calculator.init(gpa.allocator());
    defer calculator.deinit();

    main_loop: while (true) {
        try stdout.print("Equation: ", .{});
        const input = stdin.readUntilDelimiter(buf[0..], '\n') catch |err| {
            if (err != error.EndOfStream)
                try stdout.print("\nAn error occured: {s}\n", .{@errorName(err)});

            break :main_loop;
        };

        if (shouldExit(input)) break :main_loop;

        const result = calculator.calculate(input, evaluate_depth, verbosity) catch |err| {
            try stdout.print("Error: {s}\n", .{@errorName(err)});
            continue :main_loop;
        };
        if (result != null) {
            try stdout.print("Result: {s}\n", .{result.?});
            gpa.allocator().free(result.?);
        }
    }
}

fn parseArgs(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();

    const allocator = arena.allocator();

    var iterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iterator.deinit();
    _ = iterator.next();

    while (iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--evaluate-depth")) {
            const depth = iterator.next() orelse continue;
            if (std.mem.eql(u8, depth, "tokenize")) {
                evaluate_depth = .Tokenize;
            } else if (std.mem.eql(u8, depth, "parse")) {
                evaluate_depth = .Parse;
            } else if (std.mem.eql(u8, depth, "calculate")) {
                evaluate_depth = .Calculate;
            } else return error.UnknownEvaluateDepth;
        } else if (std.mem.eql(u8, arg, "--verbosity")) {
            const verb = iterator.next() orelse continue;
            if (std.mem.eql(u8, verb, "tokens")) {
                verbosity = .PrintTokens;
            } else if (std.mem.eql(u8, verb, "ast")) {
                verbosity = .PrintAst;
            } else if (std.mem.eql(u8, verb, "all")) {
                verbosity = .PrintAll;
            } else return error.UnknownVerbosity;
        } else return error.UnknownArgument;
    }
}

fn shouldExit(input: []const u8) bool {
    if (input.len < 4) return false;

    for (input) |item, index| {
        if (item == '\n' or item == '\r') continue;
        if (item != exitInput[index]) return false;
    }
    return true;
}

//                             (stdout writer)
pub fn showErrorPos(stdout: *const std.io.Writer(std.fs.File, std.os.WriteError, std.fs.File.write), startPos: usize, errorIndex: usize, err: anyerror) !void {
    var i: usize = 0;
    while (i < errorIndex + startPos) : (i += 1)
        try stdout.print(" ", .{});

    try stdout.print("^\n", .{});
    try stdout.print("Error at {d}: {s}\n", .{ errorIndex, @errorName(err) });
}
