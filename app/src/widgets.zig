const std = @import("std");
const win32 = @import("win32.zig");

pub const TextAreaOptions = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 100,
    height: i32 = 100,
    allocator: std.mem.Allocator,
};

pub const TextArea = struct {
    const Self = @This();

    hwnd: win32.HWND,
    arena: std.heap.ArenaAllocator,

    pub fn create(parent_hwnd: *const win32.HWND, hInstance: *const win32.HINSTANCE, options: TextAreaOptions) !Self {
        const hwnd = try win32.createWindowExA(
            win32.WS_EX_LEFT,
            "EDIT",
            "",
            win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.ES_MULTILINE,
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

    pub fn setText(self: *TextArea, text: []const u8) void {
        const allocator = self.arena.allocator();
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);

        if (win32.SetWindowTextW(self.hwnd, wide) == 0) {
            std.os.windows.unexpectedError(win32.GetLastError()) catch {};
        }
    }

    pub fn getText(self: *TextArea) [:0]const u8 {
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
