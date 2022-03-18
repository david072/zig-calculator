const std = @import("std");

const calculator = @import("calculator");

const allowedCharacters = "+-*/=.,()_:0123456789abcdefghijklmnopqrstuvwxyz\n\r ";
const exitInput = "exit";

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [100]u8 = undefined;

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    calculator.init(gpa.allocator());

    defer {
        calculator.deinit();
        // TODO: Get rid of the fucking memory leaks that are somewhereeeeee
        _ = gpa.deinit();
    }

    main_loop: while (true) {
        try stdout.print("Equation: ", .{});
        const input = stdin.readUntilDelimiter(buf[0..], '\n') catch |err| {
            if (err != error.EndOfStream)
                try stdout.print("\nAn error occured: {s}\n", .{@errorName(err)});

            break :main_loop;
        };

        const invalidCharacterIndex = validateInput(input);
        if (invalidCharacterIndex) |index| {
            try showErrorPos(&stdout, 10, index, error.InvalidCharacter);
            continue :main_loop;
        }

        if (shouldExit(input)) break :main_loop;

        // const result = try calculator.calculate(input);
        const result = calculator.calculate(input) catch |err| {
            try showErrorPos(&stdout, 10, calculator.parser.errorIndex, err);
            continue :main_loop;
        };
        if (result != null) {
            try stdout.print("Result: {s}\n", .{result.?});
            gpa.allocator().free(result.?);
        }
    }
}

fn validateInput(input: []u8) ?usize {
    for (input) |item, index| {
        if (item <= 'A' or item >= 'Z')
            if (!std.mem.containsAtLeast(u8, allowedCharacters, 1, &[_]u8{item})) return index;
    }

    return null;
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
