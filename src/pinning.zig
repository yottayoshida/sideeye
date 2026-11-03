const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const config = @import("config.zig");
const posix = @import("posix.zig");
const files = @import("files.zig");
const containment = @import("containment.zig");
const workdir = @import("workdir.zig");
const defang = @import("defang.zig");

const library = @embedFile("pin_lib");
pub const generator = "chacha20-v1";
pub const library_name = "libsideeye_pin.so";

// Empty, not unset, when no pin was asked for: a seed or an instant left in the operator's shell
// would otherwise be what a target reads.
pub var seed_hex: []const u8 = "";
pub var clock_value: []const u8 = "";
pub var preload: ?[]const u8 = null;
var claims_root: ?[]const u8 = null;
var invocation: [16]u8 = undefined;
var runs: u32 = 0;

pub fn asked(apparatus: []const []const u8) bool {
    return askedFor(apparatus, .pin_random);
}

pub fn askedClock(apparatus: []const []const u8) bool {
    return askedFor(apparatus, .pin_clock);
}

pub fn askedAny(apparatus: []const []const u8) bool {
    return asked(apparatus) or askedClock(apparatus);
}

fn askedFor(apparatus: []const []const u8, kind: std.meta.Tag(config.ApparatusEntry)) bool {
    for (apparatus) |e| switch (config.parseApparatusEntry(e)) {
        .ok => |p| if (p == kind) return true,
        .bad => {},
    };
    return false;
}

pub fn refusal(arena: std.mem.Allocator, entry: []const u8, kind: std.meta.Tag(config.ApparatusEntry), entries: []const []const u8, observe: contract.ObserveMode, work_abs: []const u8) ?workdir.Refusal {
    const what = if (kind == .pin_clock) "the wall clock" else "randomness";
    if (builtin.os.tag != .linux)
        return workdir.Refusal.print(arena, .platform_unsupported, "apparatus {s}: the engine pins {s} through a library it preloads on Linux only; on macOS the preload is the shim's alone, and " ++ contract.macos_table, .{ entry, what });
    if (observe == .supervised)
        return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: --observe supervised loads nothing into the operation, so there is nothing to pin through; the default mode and syscalls load the pin beside the shim", .{entry});
    if (std.mem.indexOfAny(u8, work_abs, " \t:") != null)
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: the work directory {s} holds a space, a tab or a colon, which LD_PRELOAD reads as a separator, so the pin library would not be loaded; name a --work without either", .{ entry, defang.textShown(arena, work_abs) });
    switch (kind) {
        .pin_clock => {
            for (entries) |e| switch (config.parseApparatusEntry(e)) {
                .ok => |p| if (p == .preload and namesFaketime(p.preload))
                    return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: the define also declares {s}, and a wall clock faked twice translates every wait twice; declare one of the two", .{ entry, e }),
                .bad => {},
            };
        },
        // Not for the clock: what the cgroup stops is a daemon left holding pinned randomness.
        else => if (containment.spawn(false) == null)
            return workdir.Refusal.print(arena, .environment, "apparatus {s}: needs a cgroup v2 the engine can create cgroups in, so that a process left holding the pinned randomness — a daemon the operation starts — is stopped with the run", .{entry}),
    }
    return null;
}

const Instant = struct { sec: u64, nsec: u64 };

fn parseClock(s: []const u8) ?Instant {
    const dot = std.mem.indexOfScalar(u8, s, '.') orelse return null;
    if (dot == 0 or s.len - dot - 1 != 9) return null;
    for (s[0..dot]) |ch| if (!std.ascii.isDigit(ch)) return null;
    for (s[dot + 1 ..]) |ch| if (!std.ascii.isDigit(ch)) return null;
    const sec = std.fmt.parseInt(i64, s[0..dot], 10) catch return null;
    return .{ .sec = @intCast(sec), .nsec = std.fmt.parseInt(u64, s[dot + 1 ..], 10) catch unreachable };
}

fn namesFaketime(lib: []const u8) bool {
    return lib.len >= "libfake".len and (std.mem.startsWith(u8, lib, "libfaketime") or std.mem.startsWith(u8, "libfaketime", lib));
}

pub fn validClock(s: []const u8) bool {
    return parseClock(s) != null;
}

fn prepareClock(arena: std.mem.Allocator, case_clock: ?[]const u8) ?workdir.Refusal {
    const at: Instant = if (case_clock) |c| parseClock(c).? else blk: {
        var ts: std.c.timespec = undefined;
        if (posix.clock_gettime(posix.CLOCK_REALTIME, &ts) != 0)
            return workdir.Refusal.print(arena, .environment, "apparatus pin:clock: the system's wall clock could not be read", .{});
        break :blk .{ .sec = @intCast(ts.sec), .nsec = @intCast(ts.nsec) };
    };
    clock_value = std.fmt.allocPrint(arena, "{d}.{d:0>9}", .{ at.sec, at.nsec }) catch return workdir.Refusal.print(arena, .environment, "out of memory", .{});
    return null;
}

pub fn prepare(arena: std.mem.Allocator, apparatus: []const []const u8, work_abs: []const u8, shim: []const u8, case_seed: ?[]const u8, case_clock: ?[]const u8) ?workdir.Refusal {
    if (!askedAny(apparatus)) return null;
    if (askedClock(apparatus)) if (prepareClock(arena, case_clock)) |r| return r;
    const random = asked(apparatus);
    return prepareLibrary(arena, if (random) "pin:random" else "pin:clock", work_abs, shim, random, case_seed);
}

fn prepareLibrary(arena: std.mem.Allocator, entry: []const u8, work_abs: []const u8, shim: []const u8, random: bool, case_seed: ?[]const u8) ?workdir.Refusal {
    const path = std.fmt.allocPrint(arena, "{s}/{s}", .{ work_abs, library_name }) catch return workdir.Refusal.print(arena, .environment, "out of memory", .{});
    var zb: [contract.max_path]u8 = undefined;
    const z = std.mem.printSentinel(&zb, "{s}", .{path}, 0) catch
        return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: the work directory's path is too long", .{entry});
    _ = posix.unlink(z.ptr);
    if (!files.writeNewExecutable(path, library))
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: the pin library could not be written to {s}", .{ entry, defang.textShown(arena, path) });
    // The loader skips a preload it cannot map and says nothing, so a pin that did not load
    // would surface as two runs that differ, a refusal for the wrong reason. faccessat asks the
    // mount's noexec for a regular file, which is the question the loader's mmap meets.
    if (posix.access(z.ptr, posix.X_OK) != 0)
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: the pin library written to {s} cannot be executed there (a noexec mount), so the loader would skip it; name a --work on a filesystem that allows execution", .{ entry, defang.textShown(arena, path) });
    preload = std.fmt.allocPrint(arena, "{s}:{s}", .{ path, shim }) catch return workdir.Refusal.print(arena, .environment, "out of memory", .{});
    if (!random) return null;
    const root = std.fmt.allocPrint(arena, "{s}/pin-claims", .{work_abs}) catch return workdir.Refusal.print(arena, .environment, "out of memory", .{});
    // A claim's name is the root, a 16-digit invocation, a run number and a 32-digit key: a root
    // that leaves no room for it would leave every process unpinned for a reason nobody names.
    if (root.len + 1 + 16 + 1 + 10 + 1 + 32 >= contract.max_path)
        return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: the work directory's path is too long to hold the pin's claims; name a shorter --work", .{entry});
    var rb: [contract.max_path]u8 = undefined;
    const rz = std.mem.printSentinel(&rb, "{s}", .{root}, 0) catch return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: the work directory's path is too long", .{entry});
    if (posix.mkdir(rz.ptr, 0o700) != 0 and std.c._errno().* != @backingInt(std.c.E.EXIST))
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: {s} could not be made", .{ entry, defang.textShown(arena, root) });
    // Not the run count alone: a second invocation in the same work directory would meet the
    // first one's claims under the same names and read every key as claimed twice.
    _ = posix.randomHex(&invocation) orelse return workdir.Refusal.print(arena, .environment, "apparatus {s}: the system's random source could not be read", .{entry});
    claims_root = root;
    if (case_seed) |s| {
        seed_hex = s;
        return null;
    }
    var raw: [32]u8 = undefined;
    if (posix.getentropy(&raw, raw.len) != 0)
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: the seed could not be drawn from the system's random source", .{entry});
    seed_hex = arena.dupe(u8, &std.fmt.bytesToHex(raw, .lower)) catch return workdir.Refusal.print(arena, .environment, "out of memory", .{});
    return null;
}

// One prefix per run, not one per invocation: the recording, each world and each replay claim
// the same keys, and a key claimed by an earlier run would read as one claimed twice.
pub fn claimsFor(arena: std.mem.Allocator) []const u8 {
    const root = claims_root orelse return "";
    runs += 1;
    return std.fmt.allocPrint(arena, "{s}/{s}-{d}.", .{ root, &invocation, runs }) catch "";
}

pub fn validSeed(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |ch| if (!std.ascii.isDigit(ch) and !(ch >= 'a' and ch <= 'f')) return false;
    return true;
}

test "only a lowercase 64-digit hex string is a seed" {
    try std.testing.expect(validSeed("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"));
    try std.testing.expect(!validSeed("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"));
    try std.testing.expect(!validSeed("00"));
    try std.testing.expect(!validSeed(""));
}

test "libfaketime is recognised by any prefix of its name a preload: entry can spell, and nothing shorter" {
    try std.testing.expect(namesFaketime("libfaketime"));
    try std.testing.expect(namesFaketime("libfaketime.so.1"));
    try std.testing.expect(namesFaketime("libfake"));
    try std.testing.expect(!namesFaketime("lib"));
    try std.testing.expect(!namesFaketime("libfakeroot"));
    try std.testing.expect(!namesFaketime("libsideeye_pin.so"));
}

test "a pinned instant is decimal seconds, a dot and nine digits" {
    try std.testing.expect(validClock("1793692576.123456789"));
    try std.testing.expect(!validClock("1793692576.5"));
    try std.testing.expect(!validClock(".123456789"));
    try std.testing.expect(!validClock("99999999999999999999.000000000"));
}

test "a define asks for the pin only through pin:random" {
    try std.testing.expect(asked(&.{ "note:x", "pin:random" }));
    try std.testing.expect(!asked(&.{ "note:pin:random", "env:X" }));
}
