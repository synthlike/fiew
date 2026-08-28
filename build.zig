const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fiew = b.addModule("fiew", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Opt-in git integration tests. Off by default so `zig build test` stays
    // deterministic and does not require the git executable.
    const git_integration = b.option(
        bool,
        "git-integration",
        "Run git integration tests (requires the git executable)",
    ) orelse false;
    const performance = b.option(
        bool,
        "performance",
        "Run opt-in v0.1 scale profiling tests",
    ) orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "git_integration", git_integration);
    build_options.addOption(bool, "performance", performance);
    fiew.addOptions("build_options", build_options);

    // Tree-sitter core (v0.26.13) and the Zig grammar (ABI 15) are vendored at
    // pinned revisions under vendor/ and statically compiled into the fiew
    // module. They are reached only through the direct C adapter in
    // src/adapters/treesitter. See each vendor/*/REVISION for the exact commit.
    const c_flags = &[_][]const u8{ "-std=c11", "-O2" };
    fiew.addCSourceFile(.{ .file = b.path("vendor/tree-sitter/lib/src/lib.c"), .flags = c_flags });
    fiew.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    fiew.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
    fiew.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = c_flags,
    });
    fiew.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    // The grammar's fold query lives outside src/, so expose it as a named
    // import the adapter can @embedFile.
    fiew.addAnonymousImport("zig_fold_query", .{
        .root_source_file = b.path("vendor/tree-sitter-zig/queries/folds.scm"),
    });

    const vaxis_dependency = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const executable_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fiew", .module = fiew },
            .{ .name = "vaxis", .module = vaxis_dependency.module("vaxis") },
        },
    });

    const executable = b.addExecutable(.{
        .name = "fiew",
        .root_module = executable_module,
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |arguments| run_command.addArgs(arguments);

    const run_step = b.step("run", "Run fiew");
    run_step.dependOn(&run_command.step);

    const core_tests = b.addTest(.{ .root_module = fiew });
    const run_core_tests = b.addRunArtifact(core_tests);

    const executable_tests = b.addTest(.{ .root_module = executable_module });
    const run_executable_tests = b.addRunArtifact(executable_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_executable_tests.step);
}
