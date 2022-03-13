const std = @import("std");

pub fn registerExe(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) *std.build.LibExeObjStep {
    const exe = b.addExecutable("CLI-Calculator", "cli/src/main.zig");
    exe.addPackagePath("calculator", "calculator/src/calculator.zig");

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

    const run_step = b.step("run", "Run the cli-app");
    run_step.dependOn(&run_cmd.step);
}
