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
    allocator: std.mem.Allocator,
    x: i32,
    y: i32,
    width: i32,
    height: i32,

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
            .allocator = options.allocator,
            .x = options.x,
            .y = options.y,
            .width = options.width,
            .height = options.height,
        };
    }

    pub fn translate(self: *Self, x: c_int, y: c_int) void {
        self.x += x;
        self.y += y;
        _ = win32.SetWindowPos(self.hwnd, null, self.x, self.y, self.width, self.height, 0);
    }

    pub fn setText(self: *Self, text: []const u8) void {
        const wide = std.unicode.utf8ToUtf16LeWithNull(self.allocator, text) catch return; // invalid utf8 or not enough memory
        defer self.allocator.free(wide);

        if (win32.SetWindowTextW(self.hwnd, wide) == 0) {
            std.os.windows.unexpectedError(win32.GetLastError()) catch {};
        }
    }

    pub fn getTextLength(self: *const Self) c_int {
        return win32.GetWindowTextLengthW(self.hwnd);
    }

    pub fn getText(self: *Self) [:0]const u8 {
        const len = self.getTextLength();
        var buf = self.allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer self.allocator.free(buf);

        const realLen = @intCast(usize, win32.GetWindowTextW(self.hwnd, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(self.allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

    pub fn destroy(self: *const Self) !void {
        try win32.destroyWindow(self.hwnd);
    }
};

pub const CalculatorRowOptions = struct {
    allocator: std.mem.Allocator,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 100,
    height: i32 = 100,
    index: u30,
};

pub const CalculatorRow = struct {
    const Self = @This();
    pub const text_field_height = 18;

    input_text_field: TextField,
    output_text_field: TextField,

    pub fn create(parent_hwnd: *const win32.HWND, hInstance: *const win32.HINSTANCE, options: CalculatorRowOptions) !Self {
        // TODO: Maybe get the text height and adjust text field height accordingly?
        var input_text_field = try TextField.create(parent_hwnd, hInstance, .{
            .allocator = options.allocator,
            .x = 0,
            .y = options.index * text_field_height,
            .width = 400,
            .height = text_field_height,
        });

        var output_text_field = try TextField.create(parent_hwnd, hInstance, .{
            .allocator = options.allocator,
            .x = 400,
            .y = options.index * text_field_height,
            .width = 230,
            .height = text_field_height,
            .editable = false,
            .alignment = .Right,
        });

        return Self{
            .input_text_field = input_text_field,
            .output_text_field = output_text_field,
        };
    }

    pub fn focus(self: *const Self) void {
        _ = win32.SetFocus(self.input_text_field.hwnd);
    }

    pub fn translate(self: *Self, x: c_int, y: c_int) void {
        self.input_text_field.translate(x, y);
        self.output_text_field.translate(x, y);
    }

    pub fn destroy(self: *const Self) !void {
        try self.input_text_field.destroy();
        try self.output_text_field.destroy();
    }
};
