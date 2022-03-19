const std = @import("std");
const win32 = @import("win32.zig");

var hInstance: win32.HINSTANCE = undefined;
var window_handle: win32.HWND = undefined;

const class_name = "calculatorWin";

// TODO: - Make some abstractions for this
//       - Use dark-mode

pub fn main() !void {
    hInstance = @ptrCast(win32.HINSTANCE, @alignCast(@alignOf(win32.HINSTANCE), win32.GetModuleHandleW(null).?));

    const initEx = win32.INITCOMMONCONTROLSEX{ .dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX), .dwICC = win32.ICC_STANDARD_CLASSES };
    const code = win32.InitCommonControlsEx(&initEx);
    if (code == 0)
        std.debug.print("Failed to initialize Common Controls.", .{});

    var wc: win32.WNDCLASSEXA = .{
        .style = 0,
        .lpfnWndProc = wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null, // TODO: LoadIcon
        .hCursor = null, // TODO: LoadCursor
        .hbrBackground = win32.GetSysColorBrush(win32.COLOR_WINDOW),
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };

    if ((try win32.registerClassExA(&wc)) == 0) {
        std.debug.print("Could not register window class {s}\n", .{class_name});
        return;
    }

    window_handle = try win32.createWindowExA(win32.WS_EX_LEFT, // dwExtStyle
        class_name, // lpClassName
        "Calculator", // lpWindowName
        win32.WS_OVERLAPPED | win32.WS_MINIMIZEBOX | win32.WS_SYSMENU, // dwStyle
        win32.CW_USEDEFAULT, // X
        win32.CW_USEDEFAULT, // Y
        650, // nWidth
        650, // nHeight
        null, // hWindParent
        null, // hMenu
        hInstance, // hInstance
        null // lpParam
    );

    _ = win32.showWindow(window_handle, win32.SW_SHOWDEFAULT);
    _ = win32.UpdateWindow(window_handle);

    var msg: win32.MSG = undefined;
    while (true) {
        if (win32.GetMessageA(&msg, null, 0, 0) <= 0)
            break; // WM_QUIT or error

        if ((msg.message & 0xFF) == 0x012) // WM_QUIT
            break;

        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

fn wndProc(hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    switch (wm) {
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            const hdc = win32.BeginPaint(hwnd, &ps);

            const str: []const u8 = "Hello World!";
            _ = win32.ExtTextOutA(hdc, @intCast(c_int, 5), @intCast(c_int, 5), 0, null, str.ptr, @intCast(win32.UINT, str.len), null);
            _ = win32.EndPaint(hwnd, &ps);
        },
        win32.WM_DESTROY => win32.PostQuitMessage(0),
        else => return win32.DefWindowProcA(hwnd, wm, wp, lp),
    }

    return 0;
}
