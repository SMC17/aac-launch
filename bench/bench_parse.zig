//! Benchmark: aac-launch parseExecLine throughput.
//!
//! Measures parse latency for representative Exec-line shapes. Reported
//! as ns_per_op and ops_per_sec. Run via `zig build bench`.
//!
//! Output format matches `stax-bench-run` expectations:
//!   bench=NAME size=SIZE ... ns_per_op=N ops_per_sec=N

const std = @import("std");
const aac = @import("aac");

const CASES = [_]struct {
    name: []const u8,
    line: []const u8,
    extras: []const []const u8,
    iters: usize,
}{
    .{ .name = "bare", .line = "firefox", .extras = &.{}, .iters = 100_000 },
    .{ .name = "multi-word", .line = "code --new-window --wait", .extras = &.{}, .iters = 100_000 },
    .{ .name = "quoted", .line = "code --new-window \"My Project Dir\"", .extras = &.{}, .iters = 50_000 },
    .{ .name = "percent-f", .line = "gvim %f", .extras = &.{"/tmp/example.txt"}, .iters = 50_000 },
    .{ .name = "percent-F-large", .line = "gimp %F", .extras = &.{ "a.png", "b.png", "c.png", "d.png", "e.png", "f.png", "g.png", "h.png" }, .iters = 20_000 },
    .{ .name = "long-line", .line = "echo a b c d e f g h i j k l m n o p q r s t u v w x y z 1 2 3 4 5 6 7 8 9 0", .extras = &.{}, .iters = 20_000 },
    .{ .name = "deprecated-codes", .line = "app %i %c %k file", .extras = &.{}, .iters = 50_000 },
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(io, &stdout_buf);
    defer stdout_w.interface.flush() catch {};
    const stdout = &stdout_w.interface;

    try stdout.writeAll("# aac-launch bench: parseExecLine (ReleaseFast, MONOTONIC ns)\n");
    for (CASES) |case| {
        const start = std.Io.Clock.real.now(io).nanoseconds;
        var i: usize = 0;
        while (i < case.iters) : (i += 1) {
            const argv = try aac.parseExecLine(allocator, case.line, case.extras);
            // Free immediately so allocator pressure is realistic.
            for (argv) |s| allocator.free(s);
            allocator.free(argv);
        }
        const end = std.Io.Clock.real.now(io).nanoseconds;
        const total_ns: u64 = @intCast(end - start);
        const ns_per_op = total_ns / case.iters;
        const ops_per_sec: u64 = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;
        try stdout.print(
            "bench=parse size={s} iters={d} total_ns={d} ns_per_op={d} ops_per_sec={d}\n",
            .{ case.name, case.iters, total_ns, ns_per_op, ops_per_sec },
        );
    }
}
