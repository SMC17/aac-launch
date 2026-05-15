const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module — also imported by the bench harness as `aac`.
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{ .name = "aac-launch", .root_module = lib_mod });
    b.installArtifact(exe);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Benchmarks — always ReleaseFast regardless of the top-level optimize.
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const bench_aac_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = bench_optimize,
        .link_libc = true,
    });
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/bench_parse.zig"),
        .target = target,
        .optimize = bench_optimize,
        .link_libc = true,
    });
    bench_mod.addImport("aac", bench_aac_mod);
    const bench_exe = b.addExecutable(.{ .name = "bench-parse", .root_module = bench_mod });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.has_side_effects = true;
    const bench_step = b.step("bench", "Run aac-launch parseExecLine benchmarks");
    bench_step.dependOn(&run_bench.step);
}
