const std = @import("std");
const win32 = @import("win32.zig");

pub const Alignment = enum(u32) {
    Left = win32.ES_LEFT,
    Right = win32.ES_RIGHT,
};

pub const TextFieldOptions = struct {
    allocator: std.mem.Allocator,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 100,
    height: i32 = 100,
    editable: bool = true,
    alignment: Alignment = .Left,
};

pub const TextField = struct {
    const Self = @This();

    hwnd: win32.HWND,
    arena: std.heap.ArenaAllocator,

    pub fn create(parent_hwnd: *const win32.HWND, hInstance: *const win32.HINSTANCE, options: TextFieldOptions) !Self {
        var style: u32 = win32.WS_CHILD | win32.WS_VISIBLE | @enumToInt(options.alignment);
        if (!options.editable) style |= win32.ES_READONLY;

        const hwnd = try win32.createWindowExA(
            win32.WS_EX_LEFT,
            "EDIT",
            "",
            style,
            options.x,
            options.y,
            options.width,
            options.height,
            parent_hwnd.*,
            null,
            hInstance.*,
            null,
        );

        return Self{
            .hwnd = hwnd,
            .arena = std.heap.ArenaAllocator.init(options.allocator),
        };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const allocator = self.arena.allocator();
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);

        if (win32.SetWindowTextW(self.hwnd, wide) == 0) {
            std.os.windows.unexpectedError(win32.GetLastError()) catch {};
        }
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const allocator = self.arena.allocator();

        const len = win32.GetWindowTextLengthW(self.hwnd);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);

        const realLen = @intCast(usize, win32.GetWindowTextW(self.hwnd, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }
};

pub const CalculatorRowOptions = struct {
    allocator: std.mem.Allocator,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 100,
    height: i32 = 100,
    index: u8,
};

pub const CalculatorRow = struct {
    const Self = @This();

    input_text_field: TextField,
    output_text_field: TextField,

    pub fn create(parent_hwnd: *const win32.HWND, hInstance: *const win32.HINSTANCE, options: CalculatorRowOptions) !Self {
        // TODO: Maybe get the text height and adjust text field height accordingly?
        var input_text_field = try TextField.create(parent_hwnd, hInstance, .{
            .allocator = options.allocator,
            .x = 0,
            .y = options.index * 18,
            .width = 400,
            .height = 18,
        });

        var output_text_field = try TextField.create(parent_hwnd, hInstance, .{
            .allocator = options.allocator,
            .x = 400,
            .y = options.index * 18,
            .width = 230,
            .height = 18,
            .editable = false,
            .alignment = .Right,
        });

        return Self{
            .input_text_field = input_text_field,
            .output_text_field = output_text_field,
        };
    }
};
