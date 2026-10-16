//! Inputs are copied out before each run, never printed after: a safety-check panic ends the
//! process, and the test runner's panic handler cannot be replaced.
//! The default seed is fixed: a random one would turn an unrelated pull request red.
//! Nothing is printed while runs pass: the build runner labels a passing test's stderr "failed command".

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
    const path_z = std.mem.printSentinel(&path_buf, "{s}/input.bin", .{dir_z}, 0) catch return error.FuzzPathTooLong;

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
    const template = std.mem.printSentinel(buf, "/tmp/sideeye-{s}-{s}-XXXXXX", .{ kind, name }, 0) catch return error.FuzzPathTooLong;
    _ = posix.mkdtemp(template.ptr) orelse return error.FuzzScratchUnavailable;
    return template;
}

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
        self.path = std.mem.printSentinel(&self.path_buf, "{s}/{s}", .{ r, file }, 0) catch return error.FuzzPathTooLong;
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

test "fuzz: the trace" {
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

test "fuzz: sideeye.toml" {
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

test "fuzz: the executable a define names" {
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
            try std.testing.expect(c.case_version >= 1 and c.case_version <= 7);
            // main.zig reads the mode with `.?`: read must not accept one that does not parse.
            if (c.observe) |m| {
                const mode = contract.ObserveMode.parse(m) orelse return error.ReadAcceptedAnUnknownMode;
                try std.testing.expect(mode != .wrappers or c.case_version == 7);
            }
            try std.testing.expect((c.define.apparatus != null) == (c.case_version == 7));
        },
        .invalid => |why| try std.testing.expect(why.len > 0),
    }
}

test "fuzz: a saved case" {
    const tail = "\"k\":7,\"ops_total\":7,\"prefix_hash\":\"718642bf3a3cb330\",\"after_class\":\"open\",\"after_path\":\"/s/state/m\",\"before_class\":\"write\",\"before_path\":\"/s/state/m\",\"violation\":\"checker\"}";
    try run({}, fuzzCase, .{ .name = "case", .max_len = fuzz_case_max }, &.{
        "{\"schema\":\"sideeye/case\",\"case_version\":1,\"sideeye_version\":\"0.3.0\",\"contract_version\":3,\"define\":{\"state\":\"/s/state\",\"operation\":\"tool run\",\"check\":\"./check.sh\"}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":3,\"sideeye_version\":\"1.0.0\",\"contract_version\":12,\"define\":{\"state\":\"/s/state\",\"setup\":[\"seed\",\"a b\"],\"operation\":[\"tool\",\"run\"],\"expected_status\":3}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":5,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"define\":{\"state\":\"/s/state\",\"operation\":[\"tool\",\"build\"],\"check\":\"/c/check.sh\",\"cwd\":null,\"scratch\":[\"m.yaml\"],\"expected_status\":0}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":6,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"observe\":\"supervised\",\"define\":{\"state\":\"/s/state\",\"operation\":\"tool\",\"marker\":\"done\",\"cwd\":\"/w\",\"scratch\":[],\"expected_status\":0}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":6,\"sideeye_version\":\"1.10.0\",\"contract_version\":19,\"observe\":\"syscalls\",\"define\":{\"state\":\"s\",\"operation\":[\"t\"],\"cwd\":null,\"scratch\":[\"a\"],\"expected_status\":1}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":4,\"sideeye_version\":\"1.4.0\",\"contract_version\":16,\"define\":{\"state\":\"/s/state\",\"setup\":\"seed\",\"operation\":\"tool run\",\"check\":[\"c\",\"x\"],\"cwd\":\"/w\",\"expected_status\":0}," ++ tail,
        "{\"schema\":\"sideeye/case\",\"case_version\":7,\"sideeye_version\":\"1.13.0\",\"contract_version\":19,\"observe\":\"wrappers\",\"define\":{\"state\":\"/s/state\",\"setup\":\"seed\",\"operation\":\"tool\",\"cwd\":null,\"scratch\":[],\"apparatus\":[\"env:XDG_DATA_HOME=/d\",\"pythonpath:sitecustomize.py\",\"note:x\"],\"expected_status\":0}," ++ tail,
    });
}

const fuzz_mcp_max = 16 * 1024;

fn fuzzMcp(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_mcp_max]u8 = undefined;
    const bytes = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    const a = as.allocator();
    // A small buffer, not the server's 256 KiB: the path that reads an over-long line must be reachable.
    var line_buf: [512]u8 = undefined;
    var lines: mcp.Lines = .{ .buf = &line_buf };
    var whole = std.mem.splitScalar(u8, bytes, '\n');
    var off: usize = 0;
    var step: usize = 1;
    while (true) {
        while (lines.next()) |item| try fuzzMcpItem(a, item, whole.next() orelse return error.LineCountDiffers);
        if (off == bytes.len) break;
        const space = lines.space();
        step = (step * 31 + bytes[off]) % 97 + 1;
        const n = @min(space.len, step, bytes.len - off);
        @memcpy(space[0..n], bytes[off..][0..n]);
        lines.commit(n);
        off += n;
    }
    if (lines.finish()) |item| try fuzzMcpItem(a, item, whole.next() orelse return error.LineCountDiffers);
    if (whole.next()) |rest| if (rest.len != 0 or whole.next() != null) return error.LineCountDiffers;
}

fn fuzzMcpItem(a: std.mem.Allocator, item: mcp.Lines.Item, whole: []const u8) !void {
    switch (item) {
        .line => |line| {
            try std.testing.expectEqualStrings(whole, line);
            try fuzzMcpLine(a, line);
        },
        .oversized => |o| {
            try std.testing.expect(whole.len > o.limit);
            try fuzzMcpReply(a, mcp.routeOversized(a, o));
            try fuzzMcpSameAsWhole(a, o, whole);
        },
    }
}

fn fuzzMcpSameAsWhole(a: std.mem.Allocator, o: mcp.Oversized, whole: []const u8) !void {
    if (o.too_deep) return;
    const trimmed = std.mem.trim(u8, whole, " \t\r");
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, trimmed, .{}) catch {
        // Not compared when a key other than the top-level `id` repeats: the streaming read cannot see it.
        if (std.json.parseFromSliceLeaky(std.json.Value, a, trimmed, .{ .duplicate_field_behavior = .use_last })) |_| {
            if (o.verdict != .unparsed) return;
        } else |_| {}
        return fuzzMcpSameReply(a, o, whole);
    };
    if (v != .object) {
        try std.testing.expectEqual(.not_object, o.verdict);
        return fuzzMcpSameReply(a, o, whole);
    }
    const id = v.object.get("id") orelse {
        try std.testing.expectEqual(.notification, o.verdict);
        return;
    };
    try std.testing.expectEqual(.request, o.verdict);
    switch (id) {
        .integer => |i| {
            try std.testing.expect(o.id == .integer);
            try std.testing.expectEqual(i, o.id.integer);
        },
        .string => |s| if (s.len <= mcp.IdFinder.max_id) {
            try std.testing.expect(o.id == .string);
            try std.testing.expectEqualStrings(s, o.id.string);
        },
        else => try std.testing.expect(o.id == .null),
    }
}

fn fuzzMcpSameReply(a: std.mem.Allocator, o: mcp.Oversized, whole: []const u8) !void {
    const short = mcp.route(a, whole);
    const long = mcp.routeOversized(a, o);
    switch (short) {
        .reply => |r| {
            try std.testing.expect(long == .reply);
            try std.testing.expectEqualStrings(r, long.reply);
        },
        .none => try std.testing.expect(long == .none),
        .call => return error.ShortLineWasACall,
    }
}

fn fuzzMcpLine(a: std.mem.Allocator, line: []const u8) !void {
    try fuzzMcpReply(a, mcp.route(a, line));
}

fn fuzzMcpReply(a: std.mem.Allocator, r: mcp.Route) !void {
    switch (r) {
        .none, .call => {},
        .reply => |text| {
            try std.testing.expect(std.mem.indexOfScalar(u8, text, '\n') == null);
            const v = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
            try std.testing.expectEqualStrings("2.0", v.object.get("jsonrpc").?.string);
        },
    }
}

test "fuzz: the MCP transport" {
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
        // Not only short seeds: below the entry point's 512-byte buffer the streaming read is never reached.
        "{\"method\":\"tools/call\",\"params\":{" ++ meta ++ ",\"name\":\"sideeye_preflight\",\"arguments\":{\"config_path\":\"" ++ repeat("d/", 200) ++ "sideeye.toml\",\"id\":9}},\"jsonrpc\":\"2.0\",\"id\":42}\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":\"q\\u0022\\n\",\"method\":\"tools/call\",\"params\":{\"pad\":[" ++ repeat("[1,{\"a\":null}],", 40) ++ "true]}}\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"reason\":\"" ++ @as([600]u8, @splat('r')) ++ "\"}}\n",
    });
}

const fuzz_strace_max = 16 * 1024;

// The seeds' own paths: any other state root and every line stops at the scope check, and a
// mutation that is not coverage-guided never gets past it.
fn parseStrace(a: std.mem.Allocator, input: []const u8) !parsers.oracle.Parsed {
    parsers.oracle.fold_restarted = input[0] & 1 != 0;
    const alt: []const u8 = if (input[0] & 2 != 0) "/var/o/state" else "";
    return parsers.oracle.parse(a, input[1..], "/tmp/o/state", alt, "/work");
}

fn fuzzStrace(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_strace_max]u8 = undefined;
    const input = buf[0..smith.slice(&buf)];
    if (input.len == 0) return;
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    // The first byte picks what production sets around the reader: `--observe supervised`'s
    // restarted-call folding, and a second spelling of the state. Left at one setting, the
    // branches behind the other are never reached.
    const saved = parsers.oracle.fold_restarted;
    defer parsers.oracle.fold_restarted = saved;
    const p = parseStrace(as.allocator(), input) catch return;
    try std.testing.expectEqual(p.classes.items.len, p.names.items.len);
    try std.testing.expectEqual(p.classes.items.len, p.lines.items.len);
    try std.testing.expect(p.lines_in_scope >= p.classes.items.len);
}

const strace_rotate =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    openat(AT_FDCWD</work>, "/tmp/o/state/key.json.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/o/state/key.json.tmp>
    \\10    write(3</tmp/o/state/key.json.tmp>, "key=2\n", 6) = 6
    \\10    fsync(3</tmp/o/state/key.json.tmp>) = 0
    \\10    close(3</tmp/o/state/key.json.tmp>) = 0
    \\10    rename("/tmp/o/state/key.json.tmp", "/tmp/o/state/key.json") = 0
    \\10    unlink("/tmp/o/state/old") = 0
    \\10    clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0xffff) = 11
    \\11    exit_group(0) = ?
    \\11    +++ exited with 0 +++
    \\10    --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=11, si_uid=0, si_status=0} ---
    \\10    exit_group(0) = ?
    \\10    +++ exited with 0 +++
    \\
;

const strace_trapped =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 3
    \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_call_addr=0xffff, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
    \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 6
    \\
;

const strace_two_pids =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    write(3</tmp/o/state/a>, "x", 1) = 3
    \\11    write(4</tmp/o/state/b>, "y", 1) = 4
    \\11    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
    \\11    write(4</tmp/o/state/b>, "y", 1) = 1
    \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
    \\10    write(3</tmp/o/state/a>, "x", 1) = 1
    \\
;

const strace_restarted =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6 <unfinished ...>
    \\10    <... write resumed>) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)
    \\10    --- SIGSTOP {si_signo=SIGSTOP, si_code=SI_USER, si_pid=1, si_uid=0} ---
    \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 6
    \\
;

const strace_alt =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    openat(AT_FDCWD</work>, "/var/o/state/key.json", O_WRONLY|O_TRUNC) = 3</var/o/state/key.json>
    \\10    write(3</var/o/state/key.json>, "key=2\n", 6) = 6
    \\10    rename("/var/o/state/key.json", "/tmp/o/state/key.json.bak") = 0
    \\
;

const strace_escaped_names =
    \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
    \\10    openat(AT_FDCWD</work>, "/tmp/o/state/\343\203\207\"[{k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/o/state/\343\203\207\"[{k>
    \\10    write(3</tmp/o/state/\343\203\207\"[{k>, "v\n", 2) = 2
    \\10    openat(4</tmp/o/state/a\\>, "b<c>", O_WRONLY) = 5</tmp/o/state/a\\/b\74c\76>
    \\10    fchdir(4</tmp/o/state/a\\>) = 0
    \\10    open("k", O_WRONLY|O_CREAT, 0644) = 6</tmp/o/state/a\\/k>
    \\
;

const strace_seeds = [_][]const u8{
    "\x00" ++ strace_escaped_names,
    "\x00" ++ strace_rotate,
    "\x00" ++ strace_trapped,
    "\x00" ++ strace_two_pids,
    "\x01" ++ strace_restarted,
    "\x01" ++ strace_rotate,
    "\x02" ++ strace_alt,
    "\x03" ++ strace_rotate,
};

test "fuzz: the strace capture" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const saved = parsers.oracle.fold_restarted;
    defer parsers.oracle.fold_restarted = saved;
    for (strace_seeds) |seed| {
        const p = try parseStrace(as.allocator(), seed);
        try std.testing.expect(p.classes.items.len > 0);
    }
    parsers.oracle.fold_restarted = saved;
    try run({}, fuzzStrace, .{ .name = "strace", .max_len = fuzz_strace_max }, &strace_seeds);
}

const fuzz_fsusage_max = 16 * 1024;

fn readFsUsage(a: std.mem.Allocator, text: []const u8) !parsers.fsusage.Reading {
    return parsers.fsusage.readWithStd(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/work", &.{ 111, 112 }, &.{113}, .{ false, false, null });
}

fn fuzzFsUsage(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_fsusage_max]u8 = undefined;
    const text = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    // The seeds' own trace and sentinels: with other paths every capture stops at the sentinels
    // or at naming the subject, before anything past them is read. The rest as production passes
    // it: an empty cwd or no thread list would leave the relative operands and the thread checks
    // unreached.
    const r = readFsUsage(as.allocator(), text) catch return;
    if (r.defect == null) {
        try std.testing.expect(r.subject_tid != null);
        try std.testing.expect(parsers.fsusage.capturesPath(text, "/tmp/st/sentinel-a"));
        try std.testing.expect(parsers.fsusage.capturesPath(text, "/tmp/st/sentinel-b"));
    }
}

const fsusage_seeds = [_][]const u8{
    "10:00:00.000001  open              F=9   (RWCA__N_F__X___)  /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   (_WC_T__________)  /tmp/st/key.json.tmp   0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=5   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  fsync             F=5                                         0.000100   subj.111\n" ++
        "10:00:00.000006  close             F=5                                         0.000100   subj.111\n" ++
        "10:00:00.000007  rename                  /tmp/st/key.json.tmp                  0.000100   subj.111\n" ++
        "10:00:00.000008  unlink                  /tmp/st/old                           0.000100   subj.111\n" ++
        "10:00:00.000009  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n",
    "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   /somewhere/else                       0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=5   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n",
    "10:00:00.000001  open              F=9   (RWCA__N_F__X___)  /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   (_WC_TE__F______)  private/var/folders/T/tool.log   0.000100   subj.111\n" ++
        "10:00:00.000004  dup2              F=5   F=1                                   0.000100   subj.111\n" ++
        "10:00:00.000005  write             F=1   B=0x4                                 0.000100   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n",
    "10:00:00.000001  open              F=9   (RWCA__N_F__X___)  /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   (_WC_T__________)  [-2]/build.log           0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=5   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  write             F=1   B=0x3                                 0.000100   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n",
    "10:00:00.000001  open              F=9   (RWCA__N_F__X___)  /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=6   (_WC_T__________)  /tmp/st/part.json      0.000100   subj.112\n" ++
        "10:00:00.000004  write             F=6   B=0x5                                 0.000100   subj.112\n" ++
        "10:00:00.000005  open              F=7   (R_____________)  /tmp/st/part.json      0.000100   subj.113\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n",
};

test "fuzz: the fs_usage capture" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    for (fsusage_seeds) |seed| {
        const r = try readFsUsage(as.allocator(), seed);
        try std.testing.expect(r.defect == null);
    }
    try run({}, fuzzFsUsage, .{ .name = "fsusage", .max_len = fuzz_fsusage_max }, &fsusage_seeds);
}

const fuzz_evidence_max = 16 * 1024;

fn fuzzEvidence(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [fuzz_evidence_max]u8 = undefined;
    const text = buf[0..smith.slice(&buf)];
    var as = std.heap.ArenaAllocator.init(run_allocator);
    defer as.deinit();
    const a = as.allocator();
    switch (parsers.evidence.parseBundle(a, text)) {
        .refused => |why| try std.testing.expect(why.len > 0),
        // Past the parse too: a bundle that parses and then panics where it is rendered takes
        // `sideeye mcp` down for every client.
        .ok => |ev| {
            _ = try parsers.evidence.render(a, ev);
            _ = parsers.mcp.summarizeEvidence(a, ev, .none) orelse return error.EvidenceSummaryFailed;
            const structured = parsers.mcp.evidenceStructured(a, ev, .{ .path = "/w/cases/000001.json" }) orelse return error.EvidenceStructuredFailed;
            try std.testing.expect(try std.json.validate(a, structured));
        },
    }
}

fn evidenceSeed(a: std.mem.Allocator, exhibit: anytype, rows: []const parsers.evidence.PathRow) ![]const u8 {
    const ev: parsers.evidence.Evidence = .{
        .schema = "sideeye/evidence",
        .evidence_version = parsers.evidence.current_version,
        .sideeye_version = "1.12.0",
        .contract_version = contract.contract_version,
        .target = .{ .operation = "mdl --fix README.md", .state_root = "/st" },
        .exhibit = exhibit,
        .crash_point = 2,
        .crash_points_total = 5,
        .boundary = .{ .after_op = "open", .after_path = "/st/README.md", .before_op = "write", .before_path = "/st/README.md" },
        .invariant = "built-in atomicity (L0)",
        .subject = "README.md",
        .observed = "holding neither the old nor the new content",
        .consequence = rows,
        .consequence_truncated = false,
        .checker = .{ .configured = true, .failed = true, .diagnostic = "FAIL: README.md lost \"Title\"" },
        .replay = "sideeye replay /w/cases/000001.json",
        .case = "/w/cases/000001.json",
        .recovery = .{ .result = "not_configured" },
        .caveats = &.{"No oracle confirmed it."},
    };
    return parsers.evidence.buildJson(a, ev);
}

test "fuzz: an evidence bundle" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const rows = [_]parsers.evidence.PathRow{
        .{ .path = "README.md", .before = .{ .kind = "file", .size = 61 }, .completed = .{ .kind = "file", .size = 60 }, .crashed = .{ .kind = "file", .size = 0 }, .pre_existing = true, .declared_scratch = false, .old_bytes_elsewhere = .no, .old_bytes_at = "" },
        .{ .path = "docs/a b.md", .before = null, .completed = .{ .kind = "file", .size = 3 }, .crashed = null, .pre_existing = false, .declared_scratch = true, .old_bytes_elsewhere = .unknown, .old_bytes_at = "" },
    };
    const seeds = [_][]const u8{ try evidenceSeed(a, .earliest, rows[0..1]), try evidenceSeed(a, .checker, &rows) };
    for (seeds) |seed| try std.testing.expect(parsers.evidence.parseBundle(a, seed) == .ok);
    try run({}, fuzzEvidence, .{ .name = "evidence", .max_len = fuzz_evidence_max }, &seeds);
}

fn repeat(comptime s: []const u8, comptime n: usize) *const [s.len * n]u8 {
    const out = comptime blk: {
        var buf: [s.len * n]u8 = undefined;
        for (0..n) |i| @memcpy(buf[i * s.len ..][0..s.len], s);
        break :blk buf;
    };
    return &out;
}
