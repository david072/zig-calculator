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
var calculator_row_index: u30 = 0;
var row_count: u30 = 0;

// TODO: - Use dark-mode

pub fn main() !void {
    defer _ = gpa.deinit();

    calculator_rows = std.ArrayList(widgets.CalculatorRow).init(gpa.allocator());
    defer calculator_rows.deinit();

    app = Application.init();
    try app.createWindow(class_name, "Calculator", width, height, wndProc);
    app.setPreTranslateCallback(preWndProc);
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

/// `preWndProc` gets called before `TranslateMessage` and `DispatchMessage`,
/// intercepting every message before it gets delivered to the correct window.
/// This allows us to catch key down messages, as they would otherwise only reach
/// the edit control.
fn preWndProc(msg: *const win32.MSG) void {
    if (msg.message == win32.WM_KEYDOWN) {
        switch (msg.wParam) {
            win32.VK_RETURN => {
                row_count += 1;
                calculator_row_index = row_count;

                const new_row = app.makeWidget(widgets.CalculatorRow, .{
                    .allocator = gpa.allocator(),
                    .index = row_count,
                }) catch |err| {
                    std.debug.print("Failed to create widget: {s}\n", .{@errorName(err)});
                    return;
                };

                new_row.focus();
                calculator_rows.append(new_row) catch {
                    std.debug.print("Failed to append widget to array list\n", .{});
                    return;
                };
            },
            win32.VK_UP => {
                if (calculator_row_index > 0) {
                    calculator_row_index -= 1;
                    calculator_rows.items[calculator_row_index].focus();
                }
            },
            win32.VK_DOWN => {
                if (calculator_row_index < calculator_rows.items.len - 1) {
                    calculator_row_index += 1;
                    calculator_rows.items[calculator_row_index].focus();
                }
            },
            win32.VK_BACK => {
                if (row_count == 0) return;

                const current_row = &calculator_rows.items[calculator_row_index];
                if (current_row.input_text_field.getTextLength() != 0) return;

                var i: usize = calculator_row_index + 1;
                while (i < calculator_rows.items.len) : (i += 1) {
                    // Move one text field (18) up
                    calculator_rows.items[i].translate(0, -18);
                }
                current_row.destroy() catch return;
                _ = calculator_rows.orderedRemove(calculator_row_index);

                row_count -= 1;
                if (calculator_row_index > 0) {
                    calculator_row_index -= 1;
                }
                calculator_rows.items[calculator_row_index].focus();
            },
            else => std.debug.print("other key\n", .{}),
        }
    }
}

fn wndProc(hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    return app.processEvent(hwnd, wm, wp, lp);
}
