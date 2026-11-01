const std = @import("std");
const linux = std.os.linux;

pub const std_options: std.Options = .{ .signal_stack_size = null };

const seed_var = "SIDEEYE_PIN_SEED";
const claims_var = "SIDEEYE_PIN_CLAIMS";
const ChaCha = std.crypto.stream.chacha.ChaCha20IETF;
const Sha256 = std.crypto.hash.sha2.Sha256;
const rtld_next: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
const nonce: [ChaCha.nonce_length]u8 = @splat(0);

extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern "c" fn getpid() c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn abort() noreturn;
extern "c" fn __errno_location() *c_int;
extern "c" fn fopencookie(cookie: ?*anyopaque, mode: [*:0]const u8, funcs: CookieIo) ?*anyopaque;

const Env = [*:null]const ?[*:0]const u8;
const Iovec = extern struct { base: ?[*]u8, len: usize };
const CookieIo = extern struct {
    read: ?*const fn (?*anyopaque, [*]u8, usize) callconv(.c) isize,
    write: ?*const anyopaque = null,
    seek: ?*const anyopaque = null,
    close: ?*const anyopaque = null,
};

fn Next(comptime T: type, comptime name: [:0]const u8) type {
    return struct {
        var cached: ?*anyopaque = null;
        fn get() ?T {
            var p = @atomicLoad(?*anyopaque, &cached, .acquire);
            if (p == null) {
                p = dlsym(rtld_next, name.ptr);
                @atomicStore(?*anyopaque, &cached, p, .release);
            }
            return if (p) |q| @ptrCast(@alignCast(q)) else null;
        }
    };
}

const next = struct {
    const getrandom = Next(*const fn (?*anyopaque, usize, c_uint) callconv(.c) isize, "getrandom");
    const getentropy = Next(*const fn (?*anyopaque, usize) callconv(.c) c_int, "getentropy");
    const arc4random = Next(*const fn () callconv(.c) u32, "arc4random");
    const arc4random_buf = Next(*const fn (?*anyopaque, usize) callconv(.c) void, "arc4random_buf");
    const arc4random_uniform = Next(*const fn (u32) callconv(.c) u32, "arc4random_uniform");
    const open = Next(*const fn ([*:0]const u8, c_int, c_uint) callconv(.c) c_int, "open");
    const open64 = Next(*const fn ([*:0]const u8, c_int, c_uint) callconv(.c) c_int, "open64");
    const openat = Next(*const fn (c_int, [*:0]const u8, c_int, c_uint) callconv(.c) c_int, "openat");
    const openat64 = Next(*const fn (c_int, [*:0]const u8, c_int, c_uint) callconv(.c) c_int, "openat64");
    const open_2 = Next(*const fn ([*:0]const u8, c_int) callconv(.c) c_int, "__open_2");
    const open64_2 = Next(*const fn ([*:0]const u8, c_int) callconv(.c) c_int, "__open64_2");
    const openat_2 = Next(*const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int, "__openat_2");
    const openat64_2 = Next(*const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int, "__openat64_2");
    const read = Next(*const fn (c_int, ?*anyopaque, usize) callconv(.c) isize, "read");
    const read_chk = Next(*const fn (c_int, ?*anyopaque, usize, usize) callconv(.c) isize, "__read_chk");
    const readv = Next(*const fn (c_int, [*]const Iovec, c_int) callconv(.c) isize, "readv");
    const pread = Next(*const fn (c_int, ?*anyopaque, usize, i64) callconv(.c) isize, "pread");
    const pread64 = Next(*const fn (c_int, ?*anyopaque, usize, i64) callconv(.c) isize, "pread64");
    const pread_chk = Next(*const fn (c_int, ?*anyopaque, usize, i64, usize) callconv(.c) isize, "__pread_chk");
    const preadv = Next(*const fn (c_int, [*]const Iovec, c_int, i64) callconv(.c) isize, "preadv");
    const preadv2 = Next(*const fn (c_int, [*]const Iovec, c_int, i64, c_int) callconv(.c) isize, "preadv2");
    const fopen = Next(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque, "fopen");
    const fopen64 = Next(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque, "fopen64");
    const fork = Next(*const fn () callconv(.c) c_int, "fork");
    const vfork = Next(*const fn () callconv(.c) c_int, "vfork");
    const execve = Next(*const fn ([*:0]const u8, [*]const ?[*:0]const u8, Env) callconv(.c) c_int, "execve");
    const execvpe = Next(*const fn ([*:0]const u8, [*]const ?[*:0]const u8, Env) callconv(.c) c_int, "execvpe");
    const execv = Next(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, "execv");
    const execvp = Next(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, "execvp");
    const posix_spawn = Next(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, ?Env) callconv(.c) c_int, "posix_spawn");
    const posix_spawnp = Next(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, ?Env) callconv(.c) c_int, "posix_spawnp");
    const system = Next(*const fn (?[*:0]const u8) callconv(.c) c_int, "system");
    const popen = Next(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque, "popen");
};

var key: [32]u8 = undefined;
var on: bool = false;
var owner: c_int = -1;
var pos: std.atomic.Value(u64) = .init(0);
var children: std.atomic.Value(u64) = .init(0);
var ready: std.atomic.Value(u8) = .init(0);
var vfork_hex: [64]u8 = undefined;
var vfork_from: c_int = -1;
var claims_buf: [4096]u8 = undefined;
var claims_len: usize = 0;

fn ensure() bool {
    if (ready.load(.acquire) == 2) return true;
    if (ready.cmpxchgStrong(0, 1, .acq_rel, .acquire) != null) return false;
    init();
    ready.store(2, .release);
    return true;
}

fn init() void {
    const v = getenv(seed_var) orelse return;
    const s = std.mem.span(v);
    if (s.len != 64) return;
    var raw: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&raw, s) catch return;
    const c = std.mem.span(getenv(claims_var) orelse return);
    if (c.len == 0 or c.len > claims_buf.len) return;
    @memcpy(claims_buf[0..c.len], c);
    claims_len = c.len;
    key = imageKey(raw);
    owner = getpid();
    on = claim();
    // Emptied, not left: a child started on a path this library does not wrap would read the
    // same value and draw this image's stream again; empty, it draws the real source, and the
    // two runs differ instead of agreeing on a reused stream.
    _ = setenv(seed_var, "", 1);
}

// Every key is claimed once per run, by an exclusive create under the run's own prefix. A
// second process that reaches a key already claimed — a child of a relay this library is not
// loaded into, which hands two children the one seed it was given — draws the real source
// instead: the two runs then differ and are refused, where sharing the stream would not be.
fn claim() bool {
    var h = Sha256.init(.{});
    h.update("sideeye-pin claim\x00");
    h.update(&key);
    const name = std.fmt.bytesToHex(h.finalResult()[0..16].*, .lower);
    const slash = std.mem.lastIndexOfScalar(u8, claims_buf[0..claims_len], '/') orelse return false;
    var dir: [claims_buf.len + 1]u8 = undefined;
    @memcpy(dir[0..slash], claims_buf[0..slash]);
    dir[slash] = 0;
    const prefix = claims_buf[slash + 1 .. claims_len];
    var leaf: [claims_buf.len + name.len + 1]u8 = undefined;
    @memcpy(leaf[0..prefix.len], prefix);
    @memcpy(leaf[prefix.len..][0..name.len], &name);
    leaf[prefix.len + name.len] = 0;
    // Relative to the claims directory, not to AT_FDCWD: strace prints AT_FDCWD with the working
    // directory, and a target that runs in its state directory would have the oracle read the
    // claim as a call on the state.
    const dfd = linux.openat(linux.AT.FDCWD, @ptrCast(&dir), .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (linux.errno(dfd) != .SUCCESS) return false;
    defer _ = linux.close(@intCast(dfd));
    // mknodat, not an exclusive open: under --observe syscalls a write-capable open is trapped,
    // and an exec'd image that claims before the shim has installed its handler dies of SIGSYS.
    return linux.errno(linux.mknodat(@intCast(dfd), @ptrCast(&leaf), linux.S.IFREG | 0o600, 0)) == .SUCCESS;
}

fn imageKey(seed: [32]u8) [32]u8 {
    var h = Sha256.init(.{});
    h.update("sideeye-pin image\x00");
    h.update(&seed);
    return h.finalResult();
}

fn childSeed() [32]u8 {
    const n = children.fetchAdd(1, .monotonic);
    var h = Sha256.init(.{});
    h.update("sideeye-pin child\x00");
    h.update(&key);
    h.update(std.mem.asBytes(&std.mem.nativeToLittle(u64, n)));
    return h.finalResult();
}

fn pinned() bool {
    return ensure() and on and getpid() == owner;
}

fn draw(buf: []u8) bool {
    if (!pinned()) return false;
    var off = pos.fetchAdd(buf.len, .monotonic);
    var block: [64]u8 = undefined;
    var i: usize = 0;
    while (i < buf.len) {
        ChaCha.stream(&block, @truncate(off / 64), key, nonce);
        const skip: usize = @intCast(off % 64);
        const n = @min(64 - skip, buf.len - i);
        @memcpy(buf[i..][0..n], block[skip..][0..n]);
        i += n;
        off += n;
    }
    return true;
}

fn drawWord() ?u32 {
    var w: [4]u8 = undefined;
    if (!draw(&w)) return null;
    return std.mem.readInt(u32, &w, .little);
}

export fn getrandom(buf: ?*anyopaque, len: usize, flags: c_uint) isize {
    if (len <= std.math.maxInt(isize)) if (buf) |b| if (draw(@as([*]u8, @ptrCast(b))[0..len])) return @intCast(len);
    const f = next.getrandom.get() orelse return -1;
    return f(buf, len, flags);
}

export fn getentropy(buf: ?*anyopaque, len: usize) c_int {
    if (len > 256) {
        __errno_location().* = @backingInt(linux.E.IO);
        return -1;
    }
    if (buf) |b| if (draw(@as([*]u8, @ptrCast(b))[0..len])) return 0;
    const f = next.getentropy.get() orelse return -1;
    return f(buf, len);
}

export fn arc4random() u32 {
    if (drawWord()) |w| return w;
    const f = next.arc4random.get() orelse return 0;
    return f();
}

export fn arc4random_buf(buf: ?*anyopaque, len: usize) void {
    if (buf) |b| if (draw(@as([*]u8, @ptrCast(b))[0..len])) return;
    if (next.arc4random_buf.get()) |f| f(buf, len);
}

export fn arc4random_uniform(upper: u32) u32 {
    if (!pinned()) {
        const f = next.arc4random_uniform.get() orelse return 0;
        return f(upper);
    }
    if (upper < 2) return 0;
    const min = (0 -% upper) % upper;
    while (true) {
        const r = drawWord() orelse return 0;
        if (r >= min) return r % upper;
    }
}

var tracked: [64]std.atomic.Value(c_int) = @splat(.init(-1));
var tracked_count: std.atomic.Value(usize) = .init(0);

fn isRandomPath(path: [*:0]const u8) bool {
    const p = std.mem.span(path);
    return std.mem.eql(u8, p, "/dev/urandom") or std.mem.eql(u8, p, "/dev/random");
}

fn noteOpen(fd: c_int, path: [*:0]const u8) void {
    if (fd < 0 or !isRandomPath(path) or !pinned()) return;
    for (&tracked) |*slot| {
        if (slot.cmpxchgStrong(-1, fd, .monotonic, .monotonic) == null) {
            _ = tracked_count.fetchAdd(1, .monotonic);
            return;
        }
    }
}

fn isRandomDevice(fd: c_int) bool {
    var sx: linux.Statx = undefined;
    const AT_EMPTY_PATH: u32 = 0x1000;
    if (linux.errno(linux.statx(fd, "", AT_EMPTY_PATH, .{ .TYPE = true }, &sx)) != .SUCCESS) return false;
    return linux.S.ISCHR(sx.mode) and sx.rdev_major == 1 and (sx.rdev_minor == 8 or sx.rdev_minor == 9);
}

// Checked on every read, not only at open: the number may have been closed (closefrom,
// close_range, an fdopen'd FILE's fclose) and reused for another file, which must get its
// own bytes, not this stream.
fn served(fd: c_int) bool {
    if (!on or fd < 0 or tracked_count.load(.monotonic) == 0) return false;
    for (&tracked) |*slot| {
        if (slot.load(.monotonic) != fd) continue;
        if (isRandomDevice(fd)) return pinned();
        if (slot.cmpxchgStrong(fd, -1, .monotonic, .monotonic) == null) _ = tracked_count.fetchSub(1, .monotonic);
        return false;
    }
    return false;
}

export fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const f = next.open.get() orelse return -1;
    const fd = f(path, flags, mode);
    noteOpen(fd, path);
    return fd;
}
export fn open64(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const f = next.open64.get() orelse return -1;
    const fd = f(path, flags, mode);
    noteOpen(fd, path);
    return fd;
}
export fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const f = next.openat.get() orelse return -1;
    const fd = f(dirfd, path, flags, mode);
    noteOpen(fd, path);
    return fd;
}
export fn openat64(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const f = next.openat64.get() orelse return -1;
    const fd = f(dirfd, path, flags, mode);
    noteOpen(fd, path);
    return fd;
}
export fn __open_2(path: [*:0]const u8, flags: c_int) c_int {
    const f = next.open_2.get() orelse return -1;
    const fd = f(path, flags);
    noteOpen(fd, path);
    return fd;
}
export fn __open64_2(path: [*:0]const u8, flags: c_int) c_int {
    const f = next.open64_2.get() orelse return -1;
    const fd = f(path, flags);
    noteOpen(fd, path);
    return fd;
}
export fn __openat_2(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    const f = next.openat_2.get() orelse return -1;
    const fd = f(dirfd, path, flags);
    noteOpen(fd, path);
    return fd;
}
export fn __openat64_2(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    const f = next.openat64_2.get() orelse return -1;
    const fd = f(dirfd, path, flags);
    noteOpen(fd, path);
    return fd;
}

fn fill(buf: ?*anyopaque, n: usize) bool {
    const b = buf orelse return n == 0;
    return draw(@as([*]u8, @ptrCast(b))[0..n]);
}

fn fillVec(iov: [*]const Iovec, cnt: c_int) ?isize {
    var total: usize = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(@max(cnt, 0)))) : (i += 1) {
        if (iov[i].base) |b| if (!draw(b[0..iov[i].len])) return null;
        total += iov[i].len;
    }
    return @intCast(total);
}

export fn read(fd: c_int, buf: ?*anyopaque, n: usize) isize {
    if (served(fd) and fill(buf, n)) return @intCast(n);
    const f = next.read.get() orelse return -1;
    return f(fd, buf, n);
}
export fn __read_chk(fd: c_int, buf: ?*anyopaque, n: usize, buflen: usize) isize {
    if (n <= buflen and served(fd) and fill(buf, n)) return @intCast(n);
    const f = next.read_chk.get() orelse return -1;
    return f(fd, buf, n, buflen);
}
export fn readv(fd: c_int, iov: [*]const Iovec, cnt: c_int) isize {
    if (served(fd)) if (fillVec(iov, cnt)) |r| return r;
    const f = next.readv.get() orelse return -1;
    return f(fd, iov, cnt);
}
export fn pread(fd: c_int, buf: ?*anyopaque, n: usize, off: i64) isize {
    if (served(fd) and fill(buf, n)) return @intCast(n);
    const f = next.pread.get() orelse return -1;
    return f(fd, buf, n, off);
}
export fn pread64(fd: c_int, buf: ?*anyopaque, n: usize, off: i64) isize {
    if (served(fd) and fill(buf, n)) return @intCast(n);
    const f = next.pread64.get() orelse return -1;
    return f(fd, buf, n, off);
}
export fn __pread_chk(fd: c_int, buf: ?*anyopaque, n: usize, off: i64, buflen: usize) isize {
    if (n <= buflen and served(fd) and fill(buf, n)) return @intCast(n);
    const f = next.pread_chk.get() orelse return -1;
    return f(fd, buf, n, off, buflen);
}
export fn preadv(fd: c_int, iov: [*]const Iovec, cnt: c_int, off: i64) isize {
    if (served(fd)) if (fillVec(iov, cnt)) |r| return r;
    const f = next.preadv.get() orelse return -1;
    return f(fd, iov, cnt, off);
}
export fn preadv2(fd: c_int, iov: [*]const Iovec, cnt: c_int, off: i64, flags: c_int) isize {
    if (served(fd)) if (fillVec(iov, cnt)) |r| return r;
    const f = next.preadv2.get() orelse return -1;
    return f(fd, iov, cnt, off, flags);
}

fn cookieRead(_: ?*anyopaque, buf: [*]u8, size: usize) callconv(.c) isize {
    if (draw(buf[0..size])) return @intCast(size);
    __errno_location().* = @backingInt(linux.E.IO);
    return -1;
}

fn openStream(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (!isRandomPath(path) or !pinned()) return null;
    return fopencookie(null, mode, .{ .read = &cookieRead });
}

export fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (openStream(path, mode)) |s| return s;
    const f = next.fopen.get() orelse return null;
    return f(path, mode);
}
export fn fopen64(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (openStream(path, mode)) |s| return s;
    const f = next.fopen64.get() orelse return null;
    return f(path, mode);
}

export fn fork() c_int {
    const f = next.fork.get() orelse return -1;
    const child: ?[32]u8 = if (pinned()) childSeed() else null;
    const rc = f();
    if (rc == 0) if (child) |s| {
        key = imageKey(s);
        pos.store(0, .monotonic);
        children.store(0, .monotonic);
        owner = getpid();
        on = claim();
    };
    return rc;
}

// Prepared before the call and tail-jumped, as the shim's vfork is: a frame of this wrapper
// spanning vfork's double return is overwritten by the child and corrupts the parent.
export fn vfork() c_int {
    if (pinned()) {
        vfork_hex = std.fmt.bytesToHex(childSeed(), .lower);
        @atomicStore(c_int, &vfork_from, owner, .release);
    }
    const f = next.vfork.get() orelse return -1;
    return @call(.always_tail, f, .{});
}

const max_env = 512;
const Carry = struct {
    entry: [seed_var.len + 1 + 64 + 1]u8 = undefined,
    ptrs: [max_env + 2]?[*:0]const u8 = undefined,
};

fn carryValue(out: *[64]u8) bool {
    if (!ensure() or !on) return false;
    if (getpid() == owner) {
        out.* = std.fmt.bytesToHex(childSeed(), .lower);
        return true;
    }
    // A vfork child shares the parent's memory: the value was prepared by the parent, and
    // nothing here may advance the parent's counters.
    if (@atomicLoad(c_int, &vfork_from, .acquire) == owner) {
        out.* = vfork_hex;
        @atomicStore(c_int, &vfork_from, -1, .release);
        return true;
    }
    return false;
}

fn refuseCarry() noreturn {
    const msg = "sideeye pin: the environment passed to a child holds more than 512 entries, so the pin's seed could not be carried\n";
    _ = linux.write(2, msg, msg.len);
    abort();
}

fn carried(c: *Carry, envp: Env) Env {
    var hex: [64]u8 = undefined;
    const have = carryValue(&hex);
    @memcpy(c.entry[0 .. seed_var.len + 1], seed_var ++ "=");
    var len: usize = seed_var.len + 1;
    if (have) {
        @memcpy(c.entry[len..][0..64], &hex);
        len += 64;
    }
    c.entry[len] = 0;
    var n: usize = 0;
    var i: usize = 0;
    while (envp[i]) |kv| : (i += 1) {
        if (std.mem.startsWith(u8, std.mem.span(kv), seed_var ++ "=")) continue;
        if (n >= max_env) refuseCarry();
        c.ptrs[n] = kv;
        n += 1;
    }
    c.ptrs[n] = @ptrCast(&c.entry);
    c.ptrs[n + 1] = null;
    return @ptrCast(&c.ptrs);
}

export fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: Env) c_int {
    const f = next.execve.get() orelse return -1;
    if (!ensure() or !on) return f(path, argv, envp);
    var c: Carry = .{};
    return f(path, argv, carried(&c, envp));
}

export fn execvpe(file: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: Env) c_int {
    const f = next.execvpe.get() orelse return -1;
    if (!ensure() or !on) return f(file, argv, envp);
    var c: Carry = .{};
    return f(file, argv, carried(&c, envp));
}

export fn posix_spawn(pid: ?*anyopaque, path: [*:0]const u8, fa: ?*const anyopaque, attr: ?*const anyopaque, argv: [*]const ?[*:0]const u8, envp: ?Env) c_int {
    const f = next.posix_spawn.get() orelse return 38;
    const e = envp orelse return f(pid, path, fa, attr, argv, envp);
    if (!ensure() or !on) return f(pid, path, fa, attr, argv, e);
    var c: Carry = .{};
    return f(pid, path, fa, attr, argv, carried(&c, e));
}

export fn posix_spawnp(pid: ?*anyopaque, file: [*:0]const u8, fa: ?*const anyopaque, attr: ?*const anyopaque, argv: [*]const ?[*:0]const u8, envp: ?Env) c_int {
    const f = next.posix_spawnp.get() orelse return 38;
    const e = envp orelse return f(pid, file, fa, attr, argv, envp);
    if (!ensure() or !on) return f(pid, file, fa, attr, argv, e);
    var c: Carry = .{};
    return f(pid, file, fa, attr, argv, carried(&c, e));
}

// Not done in a vfork child: setenv there would reallocate the suspended parent's environment.
fn withEnvironValue(comptime R: type, call: anytype, args: anytype) R {
    if (!pinned()) return @call(.auto, call, args);
    var hex: [65]u8 = undefined;
    hex[0..64].* = std.fmt.bytesToHex(childSeed(), .lower);
    hex[64] = 0;
    _ = setenv(seed_var, @ptrCast(&hex), 1);
    const r = @call(.auto, call, args);
    const saved = __errno_location().*;
    _ = setenv(seed_var, "", 1);
    __errno_location().* = saved;
    return r;
}

export fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int {
    const f = next.execv.get() orelse return -1;
    return withEnvironValue(c_int, f, .{ path, argv });
}

export fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int {
    const f = next.execvp.get() orelse return -1;
    return withEnvironValue(c_int, f, .{ file, argv });
}

export fn system(cmd: ?[*:0]const u8) c_int {
    const f = next.system.get() orelse return -1;
    return withEnvironValue(c_int, f, .{cmd});
}

export fn popen(cmd: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    const f = next.popen.get() orelse return null;
    return withEnvironValue(?*anyopaque, f, .{ cmd, mode });
}

fn ctor() callconv(.c) void {
    _ = ensure();
    inline for (comptime std.meta.declarations(next)) |name| _ = @field(next, name).get();
}

export const sideeye_pin_init_array: *const fn () callconv(.c) void linksection(".init_array") = &ctor;

test "two children of one image draw different seeds, and a child's image key is not its parent's" {
    key = imageKey(@splat(7));
    children.store(0, .monotonic);
    const a = childSeed();
    const b = childSeed();
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
    try std.testing.expect(!std.mem.eql(u8, &imageKey(a), &key));
}

test "the stream is the same for the same key and position, whatever the read sizes" {
    key = imageKey(@splat(3));
    on = true;
    owner = getpid();
    ready.store(2, .release);
    defer on = false;
    var one: [100]u8 = undefined;
    pos.store(0, .monotonic);
    try std.testing.expect(draw(&one));
    var two: [100]u8 = undefined;
    pos.store(0, .monotonic);
    try std.testing.expect(draw(two[0..37]));
    try std.testing.expect(draw(two[37..]));
    try std.testing.expectEqualSlices(u8, &one, &two);
}
