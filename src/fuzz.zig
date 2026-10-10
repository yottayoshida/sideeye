//! Fuzz entry points for five readers of untrusted bytes (ADR 0112).
//! Not `zig build test --fuzz`: Zig 0.16.0's test runner does not compile under -ffuzz; the
//! entry points keep the form that fuzzer takes.
//! Inputs are copied out before each run, never printed after: a safety-check panic ends the
//! process, and the test runner's panic handler cannot be replaced.
//! The default seed is fixed: a random one would turn an unrelated pull request red.
//! Nothing is printed while runs pass: the build runner labels a passing test's stderr "failed command".
//! The entry points live here, not beside their parsers: there every test binary that reaches a
//! parser would run them again.

const std = @import("std");
const builtin = @import("builtin");
const parsers = @import("parsers");
const posix = parsers.posix;
const options = @import("fuzz_options");

pub const Target = struct {
    name: []const u8,
    /// Cut every mutation to this: Smith reads a longer declared slice as empty.
    max_len: u32,
};

pub fn smithForm(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, 4 + raw.len);
    std.mem.writeInt(u32, out[0..4], @intCast(raw.len), .little);
    @memcpy(out[4..], raw);
    return out;
}

pub fn run(
    context: anytype,
    comptime testOne: fn (@TypeOf(context), *std.testing.Smith) anyerror!void,
    target: Target,
    seeds: []const []const u8,
) !void {
    const gpa = std.testing.allocator;
    if (seeds.len == 0) return error.FuzzWithoutSeeds;
    for (seeds, 0..) |s, i| if (s.len > target.max_len) {
        std.debug.print("fuzz {s}: seed {d} is {d} bytes, over the entry point's {d}; Smith would read it as empty\n", .{ target.name, i, s.len, target.max_len });
        return error.FuzzSeedTooLong;
    };

    const corpus = try gpa.alloc([]const u8, seeds.len);
    var framed_seeds: usize = 0;
    defer {
        for (corpus[0..framed_seeds]) |c| gpa.free(c);
        gpa.free(corpus);
    }
    for (seeds) |s| {
        corpus[framed_seeds] = try smithForm(gpa, s);
        framed_seeds += 1;
    }
    try std.testing.fuzz(context, testOne, .{ .corpus = corpus });
    // Not both: in fuzz mode the fuzzer owns the entry point.
    if (builtin.fuzz) return;
    if (options.runs == 0) return;

    var dir_buf: [256]u8 = undefined;
    const dir_z = try scratchDir(&dir_buf, "fuzz", target.name);
    var path_buf: [300]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}/input.bin", .{dir_z}) catch return error.FuzzPathTooLong;

    const seed = options.seed ^ std.hash.Wyhash.hash(0, target.name);

    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const work = try gpa.alloc(u8, target.max_len);
    defer gpa.free(work);
    const framed = try gpa.alloc(u8, 4 + @as(usize, target.max_len));
    defer gpa.free(framed);
    const kept = try Kept.open(path_z, framed.len);
    defer kept.close();

    var i: u32 = 0;
    while (i < options.runs) : (i += 1) {
        const base = seeds[r.uintLessThan(usize, seeds.len)];
        var len = base.len;
        @memcpy(work[0..len], base);
        var m = mutationCount(r);
        while (m > 0) : (m -= 1) len = mutate(r, work, len, seeds);

        std.mem.writeInt(u32, framed[0..4], @intCast(len), .little);
        @memcpy(framed[4..][0..len], work[0..len]);
        const input = framed[0 .. 4 + len];
        kept.put(input);

        var smith: std.testing.Smith = .{ .in = input };
        testOne(context, &smith) catch |e| {
            std.debug.print("fuzz {s}: run {d} of {d} from seed 0x{x} failed with error.{t}; the input ({d} bytes, Smith-framed) is in {s}: {x}\n", .{ target.name, i + 1, options.runs, options.seed, e, input.len, path_z, input });
            return e;
        };
    }
    _ = posix.unlink(path_z.ptr);
    _ = posix.rmdir(dir_z.ptr);
}

/// mkdtemp, not a fixed name: a link another user placed in advance must not become the directory.
fn scratchDir(buf: []u8, kind: []const u8, name: []const u8) ![:0]const u8 {
    const template = std.fmt.bufPrintZ(buf, "/tmp/sideeye-{s}-{s}-XXXXXX", .{ kind, name }) catch return error.FuzzPathTooLong;
    _ = posix.mkdtemp(template.ptr) orelse return error.FuzzScratchUnavailable;
    return template;
}

/// A shared mapping, not a file write per run: its pages outlive a panicking process, with no
/// system call per run.
const Kept = struct {
    fd: c_int,
    map: []align(std.heap.page_size_min) u8,

    const O_RDWR: c_int = 2;

    fn open(path_z: [:0]const u8, size: usize) !Kept {
        const fd = posix.open(path_z.ptr, O_RDWR | posix.O_CREAT | posix.O_EXCL | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0o600));
        if (fd < 0) return error.FuzzInputUnwritable;
        errdefer _ = posix.close(fd);
        if (std.c.ftruncate(fd, @intCast(size)) != 0) return error.FuzzInputUnwritable;
        const rc = std.c.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
        if (rc == std.c.MAP_FAILED) return error.FuzzInputUnwritable;
        return .{ .fd = fd, .map = @as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(rc)))[0..size] };
    }

    fn put(self: Kept, input: []const u8) void {
        @memcpy(self.map[0..input.len], input);
    }

    fn close(self: Kept) void {
        _ = std.c.munmap(self.map.ptr, self.map.len);
        _ = posix.close(self.fd);
    }
};

const interesting_bytes = [_]u8{ 0, 1, 0x7f, 0x80, 0xff, '\n', '\r', '\t', ' ', '"', '\\', '\'', '[', ']', '{', '}', '=', ',', ':', '#', '/', '.', '-' };

const interesting_ints = [_]u64{
    0,          1,          0x7f,       0x80,        0xff,               0x100,              0x7fff,               0x8000, 0xffff, 0x10000,
    0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0x7fffffffffffffff, 0x8000000000000000, std.math.maxInt(u64),
};

/// Weighted toward one: each extra mutation is another chance to break a structured input at
/// its first check, before anything deep.
fn mutationCount(r: std.Random) u32 {
    return @min(8, 1 + @ctz(r.int(u32) | (1 << 7)));
}

fn mutate(r: std.Random, buf: []u8, len: usize, seeds: []const []const u8) usize {
    const cap = buf.len;
    switch (r.uintLessThan(u8, 10)) {
        0 => if (len > 0) {
            buf[r.uintLessThan(usize, len)] ^= @as(u8, 1) << r.int(u3);
        },
        1 => if (len > 0) {
            buf[r.uintLessThan(usize, len)] = r.int(u8);
        },
        2 => if (len > 0) {
            buf[r.uintLessThan(usize, len)] = interesting_bytes[r.uintLessThan(usize, interesting_bytes.len)];
        },
        3 => if (len < cap) {
            const p = r.uintAtMost(usize, len);
            std.mem.copyBackwards(u8, buf[p + 1 .. len + 1], buf[p..len]);
            buf[p] = r.int(u8);
            return len + 1;
        },
        4 => if (len > 0) {
            const p = r.uintLessThan(usize, len);
            const n = r.intRangeAtMost(usize, 1, @min(len - p, 16));
            std.mem.copyForwards(u8, buf[p .. len - n], buf[p + n .. len]);
            return len - n;
        },
        5 => if (len > 0 and len < cap) {
            const src = r.uintLessThan(usize, len);
            const n = @min(r.intRangeAtMost(usize, 1, @min(len - src, 32)), cap - len);
            var chunk: [32]u8 = undefined;
            @memcpy(chunk[0..n], buf[src..][0..n]);
            const dst = r.uintAtMost(usize, len);
            std.mem.copyBackwards(u8, buf[dst + n .. len + n], buf[dst..len]);
            @memcpy(buf[dst..][0..n], chunk[0..n]);
            return len + n;
        },
        6 => {
            const other = seeds[r.uintLessThan(usize, seeds.len)];
            const keep = r.uintAtMost(usize, len);
            const from = r.uintAtMost(usize, other.len);
            const n = @min(other.len - from, cap - keep);
            @memcpy(buf[keep..][0..n], other[from..][0..n]);
            return keep + n;
        },
        7 => if (len > 0) return r.uintLessThan(usize, len),
        8 => {
            const widths = [_]usize{ 1, 2, 4, 8 };
            const w = widths[r.uintLessThan(usize, widths.len)];
            if (w <= len) {
                const p = r.uintAtMost(usize, len - w);
                var b: [8]u8 = undefined;
                const v = interesting_ints[r.uintLessThan(usize, interesting_ints.len)];
                if (r.boolean()) {
                    std.mem.writeInt(u64, &b, v, .little);
                    @memcpy(buf[p..][0..w], b[0..w]);
                } else {
                    std.mem.writeInt(u64, &b, v, .big);
                    @memcpy(buf[p..][0..w], b[8 - w ..]);
                }
            }
        },
        9 => if (len > 0) {
            const from = seeds[r.uintLessThan(usize, seeds.len)];
            const src_bytes = if (r.boolean() or from.len == 0) buf[0..len] else from;
            buf[r.uintLessThan(usize, len)] = src_bytes[r.uintLessThan(usize, src_bytes.len)];
        },
        else => unreachable,
    }
    return len;
}

test "mutate never writes past the buffer it is given, and never returns a longer length" {
    var prng = std.Random.DefaultPrng.init(0x695);
    const r = prng.random();
    const seeds = [_][]const u8{ "", "a", "0123456789abcdef0123456789abcdef0123456789" };
    var buf: [48]u8 = undefined;
    var len: usize = 0;
    var longest: usize = 0;
    var n: usize = 0;
    while (n < 20000) : (n += 1) {
        len = mutate(r, &buf, len, &seeds);
        try std.testing.expect(len <= buf.len);
        longest = @max(longest, len);
        if (n % 97 == 0) len = 0;
    }
    try std.testing.expectEqual(buf.len, longest);
}

const contract = @import("contract");
const config = parsers.config;
const engine = parsers.engine;
const image = parsers.image;
const case = parsers.case;
const mcp = parsers.mcp;

/// Not std.testing.allocator: its DebugAllocator keeps a record of every allocation, so a long
/// run grows without bound.
const run_allocator = std.heap.c_allocator;

const DiskInput = struct {
    dir_buf: [256]u8 = undefined,
    path_buf: [1100]u8 = undefined,
    dir: [:0]const u8 = "",
    path: [:0]const u8 = "",
    mode: c_uint,
    fd: c_int = -1,

    fn init(self: *DiskInput, name: []const u8, file: []const u8) !void {
        self.dir = try scratchDir(&self.dir_buf, "fuzzfile", name);
        var real: [1024]u8 = undefined;
        const r = std.mem.span(posix.realpath(self.dir.ptr, &real) orelse return error.FuzzScratchUnavailable);
        self.path = std.fmt.bufPrintZ(&self.path_buf, "{s}/{s}", .{ r, file }) catch return error.FuzzPathTooLong;
        self.fd = posix.open(self.path.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL | posix.O_NOFOLLOW | posix.O_CLOEXEC, self.mode);
        if (self.fd < 0) return error.FuzzInputUnwritable;
    }

    fn put(self: *const DiskInput, bytes: []const u8) !void {
        var off: usize = 0;
        while (off < bytes.len) {
            const w = std.c.pwrite(self.fd, bytes[off..].ptr, bytes.len - off, @intCast(off));
            if (w <= 0) return error.FuzzInputUnwritable;
            off += @intCast(w);
        }
        if (std.c.ftruncate(self.fd, @intCast(bytes.len)) != 0) return error.FuzzInputUnwritable;
    }

    fn deinit(self: *const DiskInput) void {
        if (self.fd >= 0) _ = posix.close(self.fd);
        _ = posix.unlink(self.path.ptr);
        _ = posix.rmdir(self.dir.ptr);
    }
};

const fuzz_trace_max = 64 * 1024;

var fuzz_trace_buf: [fuzz_trace_max]u8 = undefined;

fn fuzzTrace(input: *const DiskInput, smith: *std.testing.Smith) anyerror!void {
    try input.put(fuzz_trace_buf[0..smith.slice(&fuzz_trace_buf)]);
    var budget: engine.TraceBudget = .{ .child = run_allocator, .limit = engine.max_trace_bytes_total };
    var info = try engine.readTraceCapped(&budget, input.path, engine.max_trace_bytes);
    info.deinit();
    try std.testing.expectEqual(@as(usize, 0), budget.used);
}

fn traceBytes(a: std.mem.Allocator, records: []const contract.Record) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var hbuf: [contract.header_len]u8 = undefined;
    try out.appendSlice(a, hbuf[0..try contract.encodeHeader(&hbuf)]);
    for (records) |rec| {
        var rbuf: [contract.max_record_len]u8 = undefined;
        try out.appendSlice(a, rbuf[0..try contract.encodeRecord(&rbuf, rec)]);
    }
    return out.items;
}

test "fuzz: the trace (#695)" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    var input: DiskInput = .{ .mode = 0o600 };
    try input.init("trace", "trace.bin");
    defer input.deinit();
    const seeds = [_][]const u8{
        try traceBytes(a, &.{
            .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
            .{ .op = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a.tmp", .aux = "" },
            .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a.tmp", .aux = "" },
            .{ .op = .fsync, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/a.tmp", .aux = "" },
            .{ .op = .rename, .seq = 4, .pid = 7, .tid = 7, .path = "/tmp/s/a.tmp", .aux = "/tmp/s/a" },
            .{ .op = .mkdir, .seq = 5, .pid = 7, .tid = 7, .path = "/tmp/s/d", .aux = "" },
            .{ .op = .close, .seq = 5, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        }),
        try traceBytes(a, &.{
            .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
            .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
            .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
            .{ .op = .shim_ready, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
            .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
        }),
        try traceBytes(a, &.{
            .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
            .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
            .{ .op = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
            .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/b", .aux = "" },
        }),
        try traceBytes(a, &.{
            .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = contract.cgroup_aux.held_kill },
            .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
            .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
            .{ .op = .cgroup, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = contract.cgroup_aux.held },
            .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
            .{ .op = .write, .seq = 1, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "" },
            .{ .op = .cgroup, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = contract.cgroup_aux.kill_returned },
        }),
    };
    try run(&input, fuzzTrace, .{ .name = "trace", .max_len = fuzz_trace_max }, &seeds);
}

const fuzz_config_max = 16 * 1024;

fn fuzzConfig(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_config_max]u8 = undefined;
    const text = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    switch (try config.parse(as.allocator(), text)) {
        .ok => {},
        .fault => |f| {
            try std.testing.expect(f.what.len > 0);
            try std.testing.expect(f.line <= std.mem.count(u8, text, "\n") + 1);
        },
    }
}

test "fuzz: sideeye.toml (#695)" {
    try run({}, fuzzConfig, .{ .name = "config", .max_len = fuzz_config_max }, &.{
        \\# sideeye.toml
        \\[world]
        \\state = "./state"                 # the directory Sideeye snapshots and restores
        \\
        \\[define]
        \\setup     = "mytool init"         # produce the initial state
        \\operation = "mytool rotate-key"   # what Sideeye kills partway through
        \\check     = "./check.sh"          # runs after crash + restart
        \\marker    = "Recorded"            # the operation's own success claim (L1)
        ,
        \\[world]
        \\state = "./state"
        \\[define]
        \\setup     = ["./seed.sh", "two words"]
        \\operation = ["mytool", "commit", "-m", "a message with spaces"]   # argv form (ADR 0019)
        \\check     = ["./check.sh", "has # and , and [ inside"]
        \\expected_status = "3"
        \\cwd = "work"
        ,
        \\[world]
        \\state = "s"
        \\[define]
        \\operation = "op"
        \\apparatus = ["env:FAKETIME=@2024-01-01 00:00:00", "preload:libfaketime", "note:hgrc revbranchcache.mmap = no"]
        \\scratch = ["COMMIT_EDITMSG", ".hg/wcache/"]
        \\[recovery]
        \\command = "ninja -C build"   # the tool's own next start
        \\check = "./check-recovered.sh"
        ,
    });
}

const fuzz_image_max = 8 * 1024;

fn fuzzImage(input: *const DiskInput, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_image_max]u8 = undefined;
    try input.put(buf[0..smith.slice(&buf)]);
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    _ = image.reobserve(as.allocator(), input.path);
    _ = image.startable(as.allocator(), input.path, null, null);
}

test "fuzz: an executable's header (#695)" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    var input: DiskInput = .{ .mode = 0o700 };
    try input.init("image", "img");
    defer input.deinit();
    var seeds: std.ArrayList([]const u8) = .empty;
    try seeds.appendSlice(as.allocator(), try image.fuzzSeeds(as.allocator()));
    try seeds.appendSlice(as.allocator(), &.{ "#!/bin/sh -e\nexit 0\n", "#!/usr/bin/env python3\nprint()\n", "#! /bin/sh\n" });
    try run(&input, fuzzImage, .{ .name = "image", .max_len = fuzz_image_max }, seeds.items);
}

const fuzz_case_max = 16 * 1024;

fn fuzzCase(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_case_max]u8 = undefined;
    const text = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    switch (case.read(as.allocator(), text)) {
        .ok => |c| {
            try std.testing.expectEqualStrings("sideeye/case", c.schema);
            try std.testing.expect(c.case_version >= 1 and c.case_version <= 6);
            // main.zig reads the mode with `.?`: read must not accept one that does not parse.
            if (c.observe) |m| {
                const mode = contract.ObserveMode.parse(m) orelse return error.ReadAcceptedAnUnknownMode;
                try std.testing.expect(mode != .wrappers);
            }
        },
        .invalid => |why| try std.testing.expect(why.len > 0),
    }
}

test "fuzz: a saved case (#695)" {
    const tail = "\"k\":7,\"ops_total\":7,\"prefix_hash\":\"718642bf3a3cb330\",\"after_class\":\"open\",\"after_path\":\"/s/state/m\",\"before_class\":\"write\",\"before_path\":\"/s/state/m\",\"violation\":\"checker\"}";
    try run({}, fuzzCase, .{ .name = "case", .max_len = fuzz_case_max }, &.{
        "{\"schema\":\"sideeye/case\",\"case_version\":1,\"sideeye_version\":\"0.3.0\",\"contract_version\":3,\"define\":{\"state\":\"/s/state\",\"operation\":\"tool run\",\"check\":\"./check.sh\"}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":3,\"sideeye_version\":\"1.0.0\",\"contract_version\":12,\"define\":{\"state\":\"/s/state\",\"setup\":[\"seed\",\"a b\"],\"operation\":[\"tool\",\"run\"],\"expected_status\":3}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":5,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"define\":{\"state\":\"/s/state\",\"operation\":[\"tool\",\"build\"],\"check\":\"/c/check.sh\",\"cwd\":null,\"scratch\":[\"m.yaml\"],\"expected_status\":0}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":6,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"observe\":\"supervised\",\"define\":{\"state\":\"/s/state\",\"operation\":\"tool\",\"marker\":\"done\",\"cwd\":\"/w\",\"scratch\":[],\"expected_status\":0}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":6,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"observe\":\"syscalls\",\"define\":{\"state\":\"s\",\"operation\":[\"t\"],\"cwd\":null,\"scratch\":[\"a\"],\"expected_status\":1}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":4,\"sideeye_version\":\"1.4.0\",\"contract_version\":16,\"define\":{\"state\":\"/s/state\",\"setup\":\"seed\",\"operation\":\"tool run\",\"check\":[\"c\",\"x\"],\"cwd\":\"/w\",\"expected_status\":0}," ++ tail,
    });
}

const fuzz_mcp_max = 16 * 1024;

fn fuzzMcp(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_mcp_max]u8 = undefined;
    const bytes = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    const a = as.allocator();
    // A small buffer, not the server's 256 KiB: the path that drops an over-long line must be reachable.
    var line_buf: [512]u8 = undefined;
    var lines: mcp.Lines = .{ .buf = &line_buf };
    var off: usize = 0;
    var step: usize = 1;
    while (true) {
        while (lines.next()) |line| try fuzzMcpLine(a, line);
        if (off == bytes.len) break;
        const space = lines.space();
        step = (step * 31 + bytes[off]) % 97 + 1;
        const n = @min(space.len, step, bytes.len - off);
        @memcpy(space[0..n], bytes[off..][0..n]);
        lines.commit(n);
        off += n;
    }
    if (lines.finish()) |line| try fuzzMcpLine(a, line);
}

fn fuzzMcpLine(a: std.mem.Allocator, line: []const u8) !void {
    switch (mcp.route(a, line)) {
        .none, .call => {},
        .reply => |r| {
            try std.testing.expect(std.mem.indexOfScalar(u8, r, '\n') == null);
            const v = try std.json.parseFromSliceLeaky(std.json.Value, a, r, .{});
            try std.testing.expectEqualStrings("2.0", v.object.get("jsonrpc").?.string);
        },
    }
}

test "fuzz: the MCP transport (#695)" {
    const meta = "\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}";
    try run({}, fuzzMcp, .{ .name = "mcp", .max_len = fuzz_mcp_max }, &.{
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{" ++ meta ++ "}}\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{" ++ meta ++ "}}\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":1}}\n",
        "{\"jsonrpc\":\"2.0\",\"id\":\"e\",\"method\":\"tools/call\",\"params\":{" ++ meta ++ ",\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"a/sideeye.toml\",\"observe\":\"syscalls\"}}}\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{" ++ meta ++ ",\"name\":\"sideeye_preflight\",\"arguments\":{\"config_path\":\"a/sideeye.toml\",\"twice\":true}}}",
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{" ++ meta ++ ",\"name\":\"sideeye_replay_case\",\"arguments\":{\"case_path\":\"c/case.json\"}}}\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{" ++ meta ++ ",\"name\":\"sideeye_evidence\",\"arguments\":{\"case_path\":\"c/case.json\"}}}\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"1999-01-01\",\"io.modelcontextprotocol/clientCapabilities\":{}},\"name\":\"x\"}}\n",
    });
}
