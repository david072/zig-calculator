const std = @import("std");

const unit_gen = @import("calculator/unit_gen.zig");

const cli = @import("cli/build.zig");
const gui = @import("app/build.zig");
// const discord = @import("discord/build.zig");

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    try unit_gen.generate();

    // CLI mode
    const cli_exe = cli.registerExe(b, target, mode);
    cli.registerRunStep(b, cli_exe);

    // GUI mode
    const gui_exe = try gui.registerExe(b, target, mode);
    gui.registerRunStep(b, gui_exe);

    // Discord bot - Currently not working
    // const discord_exe = discord.registerExe(b, target, mode);
    // discord.registerRunStep(b, discord_exe);
}
