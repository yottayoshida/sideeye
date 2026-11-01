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

// Empty, not unset, when no pin was asked for: a seed left in the operator's shell would
// otherwise be what a target reads.
pub var seed_hex: []const u8 = "";
pub var preload: ?[]const u8 = null;
var claims_root: ?[]const u8 = null;
var invocation: [16]u8 = undefined;
var runs: u32 = 0;

pub fn asked(apparatus: []const []const u8) bool {
    for (apparatus) |e| switch (config.parseApparatusEntry(e)) {
        .ok => |p| if (p == .pin_random) return true,
        .bad => {},
    };
    return false;
}

pub fn refusal(arena: std.mem.Allocator, entry: []const u8, observe: contract.ObserveMode, work_abs: []const u8) ?workdir.Refusal {
    if (builtin.os.tag != .linux)
        return workdir.Refusal.print(arena, .platform_unsupported, "apparatus {s}: the engine pins randomness through a library it preloads on Linux only; on macOS the preload is the shim's alone, and " ++ contract.macos_table, .{entry});
    if (observe == .supervised)
        return workdir.Refusal.print(arena, .define_invalid, "apparatus {s}: --observe supervised loads nothing into the operation, so there is nothing to pin through; the default mode and syscalls load the pin beside the shim", .{entry});
    if (std.mem.indexOfAny(u8, work_abs, " \t:") != null)
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: the work directory {s} holds a space, a tab or a colon, which LD_PRELOAD reads as a separator, so the pin library would not be loaded; name a --work without either", .{ entry, defang.textShown(arena, work_abs) });
    if (containment.spawn(false) == null)
        return workdir.Refusal.print(arena, .environment, "apparatus {s}: needs a cgroup v2 the engine can create cgroups in, so that a process left holding the pinned randomness — a daemon the operation starts — is stopped with the run", .{entry});
    return null;
}

pub fn prepare(arena: std.mem.Allocator, entry: []const u8, work_abs: []const u8, shim: []const u8, case_seed: ?[]const u8) ?workdir.Refusal {
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

test "a define asks for the pin only through pin:random" {
    try std.testing.expect(asked(&.{ "note:x", "pin:random" }));
    try std.testing.expect(!asked(&.{ "note:pin:random", "env:X" }));
}
