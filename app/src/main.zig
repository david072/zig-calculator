const std = @import("std");
const win32 = @import("win32.zig");

const widgets = @import("widgets.zig");
const gui = @import("gui.zig");
const Application = gui.Application;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};

const class_name = "calculatorWin";

const width = 650;
const height = 650;
const screen_height = height - 40; // subtract title bar height
var app: Application = undefined;

var input_text_area: widgets.TextArea = undefined;
var output_text_area: widgets.TextArea = undefined;

// TODO: - Use dark-mode

pub fn main() !void {
    app = Application.init();
    try app.createWindow(class_name, "Calculator", width, height, wndProc);
    app.setPaintCallback(paint);

    input_text_area = try app.makeWidget(widgets.TextArea, .{
        .allocator = gpa.allocator(),
        .width = 400,
        .height = screen_height,
    });
    input_text_area.setText("Hello Friends! :^)");

    output_text_area = try app.makeWidget(widgets.TextArea, .{
        .allocator = gpa.allocator(),
        .x = 400,
        .width = 235, // take up rest of screen width
        .height = screen_height,
    });

    app.startEventLoop();
}

pub fn paint(paint_context: *const gui.PaintContext) void {
    const str: []const u8 = "Hello World!";
    paint_context.text(str, 5, 5);
}

fn wndProc(hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    return app.processEvent(hwnd, wm, wp, lp);
}
