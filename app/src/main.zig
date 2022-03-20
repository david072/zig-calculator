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

var calculator_rows: std.ArrayList(widgets.CalculatorRow) = undefined;

// TODO: - Use dark-mode

pub fn main() !void {
    defer _ = gpa.deinit();

    calculator_rows = std.ArrayList(widgets.CalculatorRow).init(gpa.allocator());
    defer calculator_rows.deinit();

    app = Application.init();
    try app.createWindow(class_name, "Calculator", width, height, wndProc);
    app.setPaintCallback(paint);

    try calculator_rows.append(try app.makeWidget(widgets.CalculatorRow, .{
        .allocator = gpa.allocator(),
        .index = 0,
    }));

    app.startEventLoop();
}

pub fn paint(paint_context: *const gui.PaintContext) void {
    _ = paint_context;
    // const str: []const u8 = "Hello World!";
    // paint_context.text(str, 5, 5);
}

fn wndProc(hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    return app.processEvent(hwnd, wm, wp, lp);
}
