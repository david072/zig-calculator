const std = @import("std");
const win32 = @import("win32.zig");

pub const CreateWindowError = error{ ClassRegistration, AlreadyExists, ClassDoesNotExist } || std.os.UnexpectedError;

pub const Application = struct {
    const Self = @This();

    hInstance: win32.HINSTANCE,
    window_handle: win32.HWND,
    paint_callback: ?fn (context: *const PaintContext) void = null,

    pub fn init() Self {
        const hInstance = @ptrCast(win32.HINSTANCE, @alignCast(@alignOf(win32.HINSTANCE), win32.GetModuleHandleW(null).?));

        const initEx = win32.INITCOMMONCONTROLSEX{ .dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX), .dwICC = win32.ICC_STANDARD_CLASSES };
        const code = win32.InitCommonControlsEx(&initEx);
        if (code == 0)
            std.debug.print("Failed to initialize Common Controls.", .{});

        return .{
            .hInstance = hInstance,
            .window_handle = undefined,
        };
    }

    pub fn createWindow(self: *Self, class_name: [*:0]const u8, title: [*:0]const u8, width: i32, height: i32, wnd_proc: win32.WNDPROC) CreateWindowError!void {
        var wc: win32.WNDCLASSEXA = .{
            .style = 0,
            .lpfnWndProc = wnd_proc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = self.hInstance,
            .hIcon = null, // TODO: LoadIcon
            .hCursor = null, // TODO: LoadCursor
            .hbrBackground = win32.GetSysColorBrush(win32.COLOR_WINDOW),
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };

        if ((try win32.registerClassExA(&wc)) == 0) {
            std.debug.print("Could not register window class {s}\n", .{class_name});
            return error.ClassRegistration;
        }

        const window_handle = try win32.createWindowExA(win32.WS_EX_LEFT, // dwExtStyle
            class_name, // lpClassName
            title, // lpWindowName
            win32.WS_OVERLAPPED | win32.WS_MINIMIZEBOX | win32.WS_SYSMENU, // dwStyle
            win32.CW_USEDEFAULT, // X
            win32.CW_USEDEFAULT, // Y
            width, // nWidth
            height, // nHeight
            null, // hWindParent
            null, // hMenu
            self.hInstance, // hInstance
            null // lpParam
        );

        self.window_handle = window_handle;
    }

    pub fn setPaintCallback(self: *Self, paint_callback: fn (context: *const PaintContext) void) void {
        self.paint_callback = paint_callback;
    }

    pub fn startEventLoop(self: *const Self) void {
        _ = win32.showWindow(self.window_handle, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(self.window_handle);

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

    pub fn processEvent(self: *const Self, hwnd: win32.HWND, wm: c_uint, wp: win32.WPARAM, lp: win32.LPARAM) win32.LRESULT {
        switch (wm) {
            win32.WM_PAINT => {
                if (self.paint_callback) |*cbk| {
                    const paintContext = PaintContext.begin(&hwnd);
                    cbk.*(&paintContext);
                    paintContext.end();
                }

                // var ps: win32.PAINTSTRUCT = undefined;
                // const hdc = win32.BeginPaint(hwnd, &ps);

                // const str: []const u8 = "Hello World!";
                // _ = win32.ExtTextOutA(hdc, @intCast(c_int, 5), @intCast(c_int, 5), 0, null, str.ptr, @intCast(win32.UINT, str.len), null);
                // _ = win32.EndPaint(hwnd, &ps);
            },
            win32.WM_DESTROY => win32.PostQuitMessage(0),
            else => return win32.DefWindowProcA(hwnd, wm, wp, lp),
        }

        return 0;
    }

    pub fn makeWidget(self: *const Self, comptime Widget: type, options: anytype) !Widget {
        return try @call(.{}, @field(Widget, "create"), .{ &self.window_handle, &self.hInstance, options });
    }
};

pub const PaintContext = struct {
    const Self = @This();

    hwnd: *const win32.HWND,
    paint_struct: win32.PAINTSTRUCT,
    hdc: win32.HDC,

    pub fn begin(hwnd: *const win32.HWND) Self {
        var ps: win32.PAINTSTRUCT = undefined;
        const hdc = win32.BeginPaint(hwnd.*, &ps);

        return .{
            .hwnd = hwnd,
            .paint_struct = ps,
            .hdc = hdc,
        };
    }

    pub fn text(self: *const Self, str: []const u8, x: u16, y: u16) void {
        _ = win32.ExtTextOutA(self.hdc, @intCast(c_int, x), @intCast(c_int, y), 0, null, str.ptr, @intCast(win32.UINT, str.len), null);
    }

    pub fn end(self: *const Self) void {
        _ = win32.EndPaint(self.hwnd.*, &self.paint_struct);
        _ = self;
    }
};
