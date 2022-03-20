const std = @import("std");
const windows = std.os.windows;

pub usingnamespace windows.user32;
pub usingnamespace windows.kernel32;

pub const HINSTANCE = windows.HINSTANCE;
pub const HWND = windows.HWND;
pub const HDC = windows.HDC;
pub const BOOL = windows.BOOL;
pub const RECT = windows.RECT;
pub const BYTE = windows.BYTE;
pub const WINAPI = windows.WINAPI;
pub const HBRUSH = windows.HBRUSH;
pub const UINT = windows.UINT;
pub const INT = windows.INT;
pub const WPARAM = windows.WPARAM;
pub const LPARAM = windows.LPARAM;
pub const LRESULT = windows.LRESULT;
pub const HICON = windows.HICON;
pub const LPCWSTR = windows.LPCWSTR;
pub const LONG = windows.LONG;
pub const WCHAR = windows.WCHAR;

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(WINAPI) HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(WINAPI) BOOL;
pub extern "user32" fn LoadIconW(hInstance: HINSTANCE, lpIconName: LPCWSTR) callconv(WINAPI) HICON;
pub extern "user32" fn SendMessage(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: [*:0]const u16) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*:0]const u16, nMaxCount: c_int) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(WINAPI) c_int;
pub extern "user32" fn MoveWindow(hwnd: HWND, X: c_int, y: c_int, nWidth: c_int, nHeight: c_int, bRepaint: BOOL) callconv(WINAPI) BOOL;
pub extern "user32" fn SetFocus(hwnd: ?HWND) callconv(WINAPI) ?HWND;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: ?HWND, X: c_int, Y: c_int, cx: c_int, cy: c_int, uFlag: UINT) callconv(WINAPI) BOOL;

pub const INITCOMMONCONTROLSEX = extern struct {
    dwSize: c_uint,
    dwICC: c_uint,
};
pub extern "comctl32" fn InitCommonControlsEx(picce: [*c]const INITCOMMONCONTROLSEX) callconv(WINAPI) c_int;
pub const ICC_STANDARD_CLASSES = 0x00004000;

pub extern "gdi32" fn GetSysColorBrush(nIndex: c_int) callconv(WINAPI) ?HBRUSH;
pub extern "gdi32" fn ExtTextOutA(hdc: windows.HDC, x: c_int, y: c_int, options: UINT, lprect: ?*const RECT, lpString: [*]const u8, c: UINT, lpDx: ?*const INT) callconv(WINAPI) BOOL;
pub const SIZE = extern struct {
    cx: LONG,
    cy: LONG,
};
pub extern "gdi32" fn GetTextExtentPoint32A(hdc: HDC, lpString: LPCWSTR, c: c_int, psizel: *SIZE) callconv(WINAPI) BOOL;

// system colors constants (only those that are also supported on Windows 10 are present)
pub const COLOR_WINDOW = 5;
pub const COLOR_WINDOWTEXT = 6;
pub const COLOR_HIGHLIGHT = 13;
pub const COLOR_HIGHLIGHTTEXT = 14;
pub const COLOR_3DFACE = 15;
pub const COLOR_GRAYTEXT = 17;
pub const COLOR_BTNTEXT = 18;
pub const COLOR_HOTLIGHT = 26;

// styles
pub const ES_MULTILINE = 0x0004;
pub const ES_READONLY = 0x0800;
pub const ES_LEFT = 0x0000;
pub const ES_RIGHT = 0x0002;

// notification codes
pub const EN_KILLFOCUS = 0x0200;

// key codes
pub const VK_RETURN = 0x0D;
pub const VK_UP = 0x26;
pub const VK_DOWN = 0x28;
pub const VK_BACK = 0x08;
pub const VK_CONTROL = 0x11;
