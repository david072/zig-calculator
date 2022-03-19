const std = @import("std");

pub fn registerExe(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) !*std.build.LibExeObjStep {
    const exe = b.addExecutable("GUI-Calculator", "app/src/main.zig");
    exe.addPackagePath("calculator", "calculator/src/calculator.zig");

    // try @import("lib/zgt/build.zig").install(exe, "app/lib/zgt");

    const libcommon = exe.builder.pathJoin(&.{ std.fs.path.dirname(exe.builder.zig_exe).?, "lib", "libc", "mingw", "lib-common", "gdiplus.def" });
    defer exe.builder.allocator.free(libcommon);

    std.fs.accessAbsolute(libcommon, .{}) catch |err| switch (err) {
        error.FileNotFound => try std.fs.copyFileAbsolute(exe.builder.pathFromRoot("app/res/gdiplus.def"), libcommon, .{}),
        else => {},
    };

    exe.linkSystemLibrary("comctl32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("gdiplus");

    switch (exe.target.toTarget().cpu.arch) {
        .x86_64 => exe.addObjectFile("app/res/x86_64.o"),
        //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
        else => {}, // not much of a problem as it'll just lack styling
    }

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    return exe;
}

pub fn registerRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args|
        run_cmd.addArgs(args);

    const run_step = b.step("run_gui", "Run the gui-app");
    run_step.dependOn(&run_cmd.step);
}
