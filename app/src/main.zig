const std = @import("std");
const win32 = @import("win32.zig");
const gui = @import("gui.zig");
const Application = gui.Application;

const class_name = "calculatorWin";
var app: Application = undefined;

// TODO: - Use dark-mode

pub fn main() !void {
    app = Application.init();
    try app.createWindow(class_name, "Calculator", 650, 650, wndProc);
    app.setPaintCallback(paint);
    app.startEventLoop();
}

pub fn paint(paint_context: *const gui.PaintContext) void {
    const str: []const u8 = "Hello World!";
    paint_context.text(str, 5, 5);
}

fn wndProc(hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    return app.processEvent(hwnd, wm, wp, lp);
}
