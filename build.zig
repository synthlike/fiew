const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const skaut = b.addModule("skaut", .{
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
    const zls_integration = b.option(
        bool,
        "zls-integration",
        "Run live ZLS integration tests (requires the zls executable)",
    ) orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "git_integration", git_integration);
    build_options.addOption(bool, "performance", performance);
    build_options.addOption(bool, "zls_integration", zls_integration);
    skaut.addOptions("build_options", build_options);

    // Tree-sitter core (v0.26.13), Zig, and Markdown grammars (ABI 15) are vendored at
    // pinned revisions under vendor/ and statically compiled into the skaut
    // module. They are reached only through the direct C adapter in
    // src/adapters/treesitter. See each vendor/*/REVISION for the exact commit.
    const c_flags = &[_][]const u8{
        "-std=c11",
        "-O2",
        "-D_POSIX_C_SOURCE=200809L",
        "-D_DEFAULT_SOURCE",
    };
    skaut.addCSourceFile(.{ .file = b.path("vendor/tree-sitter/lib/src/lib.c"), .flags = c_flags });
    skaut.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    skaut.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
    skaut.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = c_flags,
    });
    skaut.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    for (&[_][]const u8{
        "vendor/tree-sitter-markdown/block/parser.c",
        "vendor/tree-sitter-markdown/block/scanner.c",
        "vendor/tree-sitter-markdown/inline/parser.c",
        "vendor/tree-sitter-markdown/inline/scanner.c",
    }) |source| skaut.addCSourceFile(.{ .file = b.path(source), .flags = c_flags });
    skaut.addIncludePath(b.path("vendor/tree-sitter-markdown/block"));
    skaut.addIncludePath(b.path("vendor/tree-sitter-markdown/inline"));
    // The grammar's fold query lives outside src/, so expose it as a named
    // import the adapter can @embedFile.
    skaut.addAnonymousImport("zig_fold_query", .{
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
            .{ .name = "skaut", .module = skaut },
            .{ .name = "vaxis", .module = vaxis_dependency.module("vaxis") },
        },
    });

    const executable = b.addExecutable(.{
        .name = "skaut",
        .root_module = executable_module,
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |arguments| run_command.addArgs(arguments);

    const run_step = b.step("run", "Run Skaut");
    run_step.dependOn(&run_command.step);

    const core_tests = b.addTest(.{ .root_module = skaut });
    const run_core_tests = b.addRunArtifact(core_tests);

    const executable_tests = b.addTest(.{ .root_module = executable_module });
    const run_executable_tests = b.addRunArtifact(executable_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_executable_tests.step);

    // Emit, but do not run, target test binaries. This supports cross-building
    // on macOS and executing the exact binaries in a native Linux environment.
    const install_core_tests = b.addInstallArtifact(core_tests, .{ .dest_sub_path = "skaut-core-tests" });
    const install_executable_tests = b.addInstallArtifact(executable_tests, .{ .dest_sub_path = "skaut-executable-tests" });
    const test_binaries_step = b.step("test-binaries", "Install target test binaries without running them");
    test_binaries_step.dependOn(&install_core_tests.step);
    test_binaries_step.dependOn(&install_executable_tests.step);
}
