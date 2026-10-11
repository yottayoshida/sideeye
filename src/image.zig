//! **This module observes. It does not conclude.** Two boundaries hold that line:
//!
//!   - *Not causation.* A library-validation bit is a fact about a file, not a proof
//!     that an insertion was refused: `com.apple.security.cs.disable-library-validation`
//!     and `...allow-dyld-environment-variables` lift it, and a non-zero `platform`
//!     byte is not by itself Apple's definition of a platform binary. So the vocabulary
//!     here is "this field held this value", and the prose built from it in main.zig
//!     says no more.
//!   - *Not identity.* The kernel executes an image; we can only open a path. The
//!     measurement is taken immediately before the spawn — never after the run, when
//!     the name may resolve somewhere else entirely — and taken again at the refusal so
//!     a path that changed underneath is said out loud. What the second reading compares
//!     is the answer itself, not a stat proxy: if two observations of the same path
//!     produce the same size and the same fields, nothing this module reports would have
//!     differed, which is the only granularity its claims need. An overwrite that leaves
//!     both identical is invisible, so a match is never reported as "this is what ran",
//!     and a difference is never reported with a time: it says the two observations
//!     disagree, not that the swap happened after the run.

const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");

const max_fat_arch = 64;
const max_load_commands = 4096;
const max_sizeofcmds = 1 << 20;
const max_superblob_entries = 256;
const max_program_headers = 4096;

pub const cs_require_lv: u32 = 0x2000;
pub const cs_runtime: u32 = 0x10000;
const cs_adhoc: u32 = std.macho.CS_ADHOC;
const cs_linker_signed: u32 = std.macho.CS_LINKER_SIGNED;

const cpu_type_x86_64: i32 = 0x01000007;
const cpu_type_arm64: i32 = 0x0100000C;

pub const Signing = struct {
    flags: u32,
    platform: u8,

    pub fn libraryValidation(s: Signing) bool {
        return s.flags & cs_require_lv != 0;
    }
    pub fn hardenedRuntime(s: Signing) bool {
        return s.flags & cs_runtime != 0;
    }
    /// Non-zero means the code directory named a platform. It does NOT mean the binary
    /// is one of Apple's: their own check also requires the signature to be endorsed.
    pub fn platformNamed(s: Signing) bool {
        return s.platform != 0;
    }
};

pub const Unreadable = enum {
    no_such_file,
    permission_denied,
    not_a_regular_file,
    read_failed,
};

pub const Undecidable = enum {
    slice_not_unique,
    code_directories_disagree,
    structure_out_of_range,
};

pub const Elf = struct {
    has_interp: bool,
    class64: bool,
};

pub const MachO = struct {
    dyldlink: bool,
    signing: ?Signing,
};

pub const Facts = union(enum) {
    not_resolved: NotResolved,
    unreadable: Unreadable,
    unrecognised,
    undecidable: Undecidable,
    elf: Elf,
    macho: MachO,
};

pub const NotResolved = enum {
    path_unset,
    not_found,
};

pub const Observation = struct {
    /// The path measured, or null when `facts` is `not_resolved`. Target-derived, so
    /// every caller that prints it must send it through `textShown` first.
    path: ?[]const u8,
    /// one the define named. Not part of `sameAnswer`: a second reading takes the path as
    /// already found.
    via_path: bool = false,
    /// The file's length at the moment of the reading. Part of what `sameAnswer`
    /// compares, and never printed as a fact about the run.
    size: ?u64,
    facts: Facts,
};

pub fn sameAnswer(a: Observation, b: Observation) bool {
    if (a.size != b.size) return false;
    return std.meta.eql(a.facts, b.facts);
}

/// Measure the file `argv0` names. Call this *before* the spawn.
pub fn observe(arena: std.mem.Allocator, argv0: []const u8, cwd: ?[]const u8, path_env: ?[]const u8) Observation {
    if (std.mem.indexOfScalar(u8, argv0, '/') != null) {
        const path = resolveAgainst(arena, argv0, cwd) orelse
            return .{ .path = null, .size = null, .facts = .{ .unreadable = .read_failed } };
        return observePath(arena, path);
    }
    const env = path_env orelse
        return .{ .path = null, .size = null, .facts = .{ .not_resolved = .path_unset } };
    const buf = arena.alloc(u8, search_path_max) catch
        return .{ .path = null, .size = null, .facts = .{ .unreadable = .read_failed } };
    const found = searchPath(buf, argv0, env, cwd) orelse
        return .{ .path = null, .size = null, .facts = .{ .not_resolved = .not_found } };
    var obs = observePath(arena, found);
    obs.via_path = true;
    return obs;
}

pub const search_path_max = 4096;

/// What this does not copy from `execvp`: trying `execve` on each candidate, so a file that
/// passes the test and then fails to exec is still the answer here, where `execvp` would move
/// on to the next one only for `EACCES`; and the default list for an unset `PATH`, which the
/// caller chooses. Under `--oracle` the file that runs is found by strace's own search, which
pub fn searchPath(buf: []u8, name: []const u8, path_env: []const u8, cwd: ?[]const u8) ?[:0]const u8 {
    var s = PathSearch.init(buf, name, path_env, cwd);
    return s.next();
}

pub const PathSearch = struct {
    buf: []u8,
    name: []const u8,
    cwd: ?[]const u8,
    it: std.mem.SplitIterator(u8, .scalar),

    pub fn init(buf: []u8, name: []const u8, path_env: []const u8, cwd: ?[]const u8) PathSearch {
        return .{ .buf = buf, .name = name, .cwd = cwd, .it = std.mem.splitScalar(u8, path_env, ':') };
    }

    pub fn next(self: *PathSearch) ?[:0]const u8 {
        if (self.name.len == 0) return null;
        while (self.it.next()) |raw| {
            const dir = if (raw.len == 0) "." else raw;
            const full = if (dir[0] != '/' and self.cwd != null)
                std.fmt.bufPrintZ(self.buf, "{s}/{s}/{s}", .{ self.cwd.?, dir, self.name }) catch continue
            else
                std.fmt.bufPrintZ(self.buf, "{s}/{s}", .{ dir, self.name }) catch continue;
            if (posix.isExecutableRegular(full.ptr)) return full;
        }
        return null;
    }
};

fn observePath(arena: std.mem.Allocator, path: []const u8) Observation {
    const path_z = arena.dupeZ(u8, path) catch
        return .{ .path = path, .size = null, .facts = .{ .unreadable = .read_failed } };

    // O_NONBLOCK because the path comes from the target's own define: a FIFO there
    // would otherwise block this open until a writer appeared, i.e. forever, and the
    // engine would hang before the OS ever got to reject the exec. `posix.zig`'s flag
    const fd = posix.open(path_z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return .{
        .path = path,
        .size = null,
        .facts = .{ .unreadable = if (std.c._errno().* == posix.ENOENT)
            .no_such_file
        else
            .permission_denied },
    };
    defer _ = posix.close(fd);

    const end = posix.lseek(fd, 0, posix.SEEK_END);
    if (end < 0) return .{ .path = path, .size = null, .facts = .{ .unreadable = .not_a_regular_file } };
    const size: u64 = @intCast(end);

    return .{ .path = path, .size = size, .facts = classify(.{ .fd = fd, .size = size }) };
}

pub fn reobserve(arena: std.mem.Allocator, path: []const u8) Observation {
    const path_z = arena.dupeZ(u8, path) catch
        return .{ .path = path, .size = null, .facts = .{ .unreadable = .read_failed } };
    // O_NONBLOCK because the path comes from the target's own define: a FIFO there
    // would otherwise block this open until a writer appeared, i.e. forever, and the
    // engine would hang before the OS ever got to reject the exec. `posix.zig`'s flag
    const fd = posix.open(path_z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return .{
        .path = path,
        .size = null,
        .facts = .{ .unreadable = if (std.c._errno().* == posix.ENOENT)
            .no_such_file
        else
            .permission_denied },
    };
    defer _ = posix.close(fd);
    const end = posix.lseek(fd, 0, posix.SEEK_END);
    if (end < 0) return .{ .path = path, .size = null, .facts = .{ .unreadable = .not_a_regular_file } };
    const size: u64 = @intCast(end);
    return .{ .path = path, .size = size, .facts = classify(.{ .fd = fd, .size = size }) };
}

fn resolveAgainst(arena: std.mem.Allocator, p: []const u8, cwd: ?[]const u8) ?[]const u8 {
    if (p.len != 0 and p[0] == '/') return p;
    const base = cwd orelse return p;
    return std.fs.path.join(arena, &.{ base, p }) catch null;
}

pub const Start = struct {
    fault: Fault,
    /// nothing was judged. Define-derived, so a caller that prints it sends it through
    /// `textShown` first.
    file: ?[]const u8 = null,
    interpreter: ?[]const u8 = null,
    name: ?[]const u8 = null,
};

pub const Fault = union(enum) {
    ok,
    not_judged,
    missing,
    not_regular,
    no_exec_bit,
    /// this user may not search (EACCES), a link loop. The errno, for the message; no
    /// instruction is built from it, because "make it executable" would be the wrong one.
    unreachable_path: c_int,
    not_on_path,
};

const shebang_max = 256;

/// to `env`. Not deeper, and not wider: an `env` line with a flag or a second word is not
/// judged (Linux hands everything after the interpreter to it as ONE argument and macOS
/// splits it, so the name `env` would look for depends on the kernel), and a relative
/// interpreter is not judged either. What still reaches the exec and fails there — an image
/// built for another CPU, a second level of `env` — keeps arriving as the exit status it
/// always did.
pub fn startable(arena: std.mem.Allocator, argv0: []const u8, cwd: ?[]const u8, path_env: ?[]const u8) Start {
    if (argv0.len == 0) return .{ .fault = .not_judged };
    if (std.mem.indexOfScalar(u8, argv0, '/') != null) {
        const f = resolveAgainst(arena, argv0, cwd) orelse return .{ .fault = .not_judged };
        const fault = fileFault(arena, f);
        if (fault != .ok) return .{ .fault = fault, .file = f };
        return interpreterOf(arena, f, cwd, path_env);
    }
    const env = path_env orelse return .{ .fault = .not_judged };
    const buf = arena.alloc(u8, search_path_max) catch return .{ .fault = .not_judged };
    // candidate and `env` exits 127. `--observe supervised` and `--oracle` take the first
    // candidate and do not move on; there a broken first `#!` passes this check and fails at
    // the spawn as it always did — a refusal missed, never one added.
    var search = PathSearch.init(buf, argv0, env, cwd);
    var first: ?Start = null;
    while (search.next()) |found| {
        // no second `fileFault`. Copied: the next answer overwrites `buf`.
        const f = arena.dupe(u8, found) catch return .{ .fault = .not_judged };
        const s = interpreterOf(arena, f, cwd, path_env);
        if (s.fault == .ok or s.fault == .not_on_path) return s;
        if (first == null) first = s;
    }
    return first orelse .{ .fault = .not_on_path, .name = argv0 };
}

fn fileFault(arena: std.mem.Allocator, path: []const u8) Fault {
    const z = arena.dupeZ(u8, path) catch return .not_judged;
    if (posix.access(z.ptr, posix.F_OK) != 0) {
        const e = std.c._errno().*;
        return if (e == posix.ENOENT or e == posix.ENOTDIR) .missing else .{ .unreachable_path = e };
    }
    if (!posix.isRegularFollowing(z.ptr)) return .not_regular;
    if (posix.access(z.ptr, posix.X_OK) != 0) return .no_exec_bit;
    return .ok;
}

/// file that cannot be opened, holds no `#!`, or whose line runs past `max`. Opened
/// `O_NONBLOCK` for the reason `observePath` gives: the path is the define's, and a FIFO
/// there must not hang the engine before anything has run. The one reader of a `#!` line
fn shebangLine(arena: std.mem.Allocator, file: []const u8, comptime max: usize) ?[]const u8 {
    const z = arena.dupeZ(u8, file) catch return null;
    const fd = posix.open(z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    var buf: [max]u8 = undefined;
    const n = posix.read(fd, &buf, buf.len);
    if (n < 2) return null;
    const head = buf[0..@intCast(n)];
    if (!std.mem.startsWith(u8, head, "#!")) return null;
    const line_end = std.mem.indexOfScalar(u8, head, '\n') orelse
        (if (head.len < buf.len) head.len else return null);
    return arena.dupe(u8, head[2..line_end]) catch null;
}

fn interpreterOf(arena: std.mem.Allocator, file: []const u8, cwd: ?[]const u8, path_env: ?[]const u8) Start {
    const ok: Start = .{ .fault = .ok, .file = file };
    const line = shebangLine(arena, file, shebang_max) orelse return ok;
    var words = std.mem.tokenizeAny(u8, line, " \t");
    const interp_word = words.next() orelse return ok;
    if (interp_word[0] != '/') return ok;
    const interp = arena.dupe(u8, interp_word) catch return ok;
    const fault = fileFault(arena, interp);
    if (fault != .ok) return .{ .fault = fault, .file = file, .interpreter = interp };
    if (!std.mem.eql(u8, std.fs.path.basename(interp), "env")) return ok;
    const name_word = words.next() orelse return ok;
    if (words.next() != null) return ok;
    if (name_word[0] == '-' or std.mem.indexOfAny(u8, name_word, "=/") != null) return ok;
    const env = path_env orelse return ok;
    const sbuf = arena.alloc(u8, search_path_max) catch return ok;
    if (searchPath(sbuf, name_word, env, cwd) != null) return ok;
    return .{ .fault = .not_on_path, .file = file, .interpreter = interp, .name = arena.dupe(u8, name_word) catch return ok };
}

// What is read here is the layout that launcher relies on, read at the refusal. It observes
// and does not conclude, like the rest of this module: the operation's image sits where a
// framework's launcher sits and the framework's interpreter is there — never that a hand-off
// happened, which nothing here saw.

/// passed. Every path is the target's and goes through `textShown` before it is printed.
pub const FrameworkPython = struct {
    interpreter: []const u8,
    launcher: []const u8,
    script: ?[]const u8,
    script_options: []const u8,
    venv_launcher: ?[]const u8,
};

pub fn frameworkPython(arena: std.mem.Allocator, obs: Observation) ?FrameworkPython {
    const path = obs.path orelse return null;
    switch (obs.facts) {
        .macho => return frameworkOf(arena, path, null),
        .unrecognised => {
            const sb = shebangOf(arena, path) orelse return null;
            if (std.meta.activeTag(observePath(arena, sb.interpreter).facts) != .macho) return null;
            return frameworkOf(arena, sb.interpreter, sb);
        },
        else => return null,
    }
}

fn frameworkOf(arena: std.mem.Allocator, launcher: []const u8, script: ?Shebang) ?FrameworkPython {
    var buf: [search_path_max]u8 = undefined;
    const lz = arena.dupeZ(u8, launcher) catch return null;
    const real = std.mem.span(posix.realpath(lz.ptr, &buf) orelse return null);
    const bin = std.fs.path.dirname(real) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(bin), "bin")) return null;
    const v = std.fs.path.dirname(bin) orelse return null;
    const name = frameworkName(v);
    const lib = std.fs.path.joinZ(arena, &.{ v, name }) catch return null;
    if (posix.access(lib.ptr, posix.F_OK) != 0) return null;
    const interp = for ([_][]const u8{ name, "Python" }) |n| {
        const p = std.fs.path.joinZ(arena, &.{ v, "Resources/Python.app/Contents/MacOS", n }) catch return null;
        if (posix.isExecutableRegular(p.ptr)) break p;
    } else return null;
    return .{
        .interpreter = interp,
        .launcher = launcher,
        .script = if (script) |s| s.path else null,
        .script_options = if (script) |s| s.options else "",
        .venv_launcher = venvLauncher(arena, launcher),
    };
}

fn frameworkName(v: []const u8) []const u8 {
    const versions = std.fs.path.dirname(v) orelse return "Python";
    const bundle = std.fs.path.basename(std.fs.path.dirname(versions) orelse return "Python");
    if (!std.mem.eql(u8, std.fs.path.basename(versions), "Versions") or !std.mem.endsWith(u8, bundle, ".framework")) return "Python";
    const name = bundle[0 .. bundle.len - ".framework".len];
    return if (name.len == 0) "Python" else name;
}

fn venvLauncher(arena: std.mem.Allocator, launcher: []const u8) ?[]const u8 {
    const dir = std.fs.path.dirname(launcher) orelse return null;
    var buf: [search_path_max]u8 = undefined;
    const dz = arena.dupeZ(u8, dir) catch return null;
    const real_dir = std.mem.span(posix.realpath(dz.ptr, &buf) orelse return null);
    const value = std.fs.path.join(arena, &.{ real_dir, std.fs.path.basename(launcher) }) catch return null;
    const here = std.fs.path.joinZ(arena, &.{ real_dir, "pyvenv.cfg" }) catch return null;
    if (posix.access(here.ptr, posix.F_OK) == 0) return value;
    const up = std.fs.path.dirname(real_dir) orelse return null;
    const above = std.fs.path.joinZ(arena, &.{ up, "pyvenv.cfg" }) catch return null;
    if (posix.access(above.ptr, posix.F_OK) == 0) return value;
    return null;
}

/// What a `#!` line says: the interpreter, its first word, when that is an absolute path, and
/// whatever follows it on the line — the options the kernel hands the interpreter ahead of
/// the script (`-sE`), which a rewritten operation has to carry too (review of #703).
const Shebang = struct { interpreter: []const u8, options: []const u8, path: []const u8 };

const shebang_max_macos = 512;

fn shebangOf(arena: std.mem.Allocator, path: []const u8) ?Shebang {
    const line = shebangLine(arena, path, shebang_max_macos) orelse return null;
    var words = std.mem.tokenizeAny(u8, line, " \t");
    const word = words.next() orelse return null;
    if (word[0] != '/') return null;
    return .{ .interpreter = word, .options = std.mem.trim(u8, words.rest(), " \t\r"), .path = path };
}

const Reader = struct {
    fd: c_int,
    size: u64,

    fn at(r: Reader, off: u64, buf: []u8) bool {
        if (buf.len == 0) return true;
        _ = std.math.add(u64, off, buf.len) catch return false;
        if (off > std.math.maxInt(i64)) return false;
        const n = posix.pread(r.fd, buf.ptr, buf.len, @intCast(off));
        return n >= 0 and @as(usize, @intCast(n)) == buf.len;
    }

    fn u32At(r: Reader, off: u64, endian: std.builtin.Endian) ?u32 {
        var b: [4]u8 = undefined;
        if (!r.at(off, &b)) return null;
        return std.mem.readInt(u32, &b, endian);
    }

    fn u64At(r: Reader, off: u64, endian: std.builtin.Endian) ?u64 {
        var b: [8]u8 = undefined;
        if (!r.at(off, &b)) return null;
        return std.mem.readInt(u64, &b, endian);
    }

    fn u16At(r: Reader, off: u64, endian: std.builtin.Endian) ?u16 {
        var b: [2]u8 = undefined;
        if (!r.at(off, &b)) return null;
        return std.mem.readInt(u16, &b, endian);
    }

    fn u8At(r: Reader, off: u64) ?u8 {
        var b: [1]u8 = undefined;
        if (!r.at(off, &b)) return null;
        return b[0];
    }
};

fn classify(r: Reader) Facts {
    var magic: [4]u8 = undefined;
    if (!r.at(0, &magic)) return .unrecognised;

    if (std.mem.eql(u8, &magic, "\x7fELF")) return classifyElf(r);

    const be = std.mem.readInt(u32, &magic, .big);
    if (be == std.macho.FAT_MAGIC or be == std.macho.FAT_MAGIC_64) return classifyFat(r, be == std.macho.FAT_MAGIC_64);

    const le = std.mem.readInt(u32, &magic, .little);
    if (le == std.macho.MH_MAGIC_64 or le == std.macho.MH_MAGIC) return classifyMachOSlice(r, 0);
    if (be == std.macho.MH_MAGIC_64 or be == std.macho.MH_MAGIC) return classifyMachOSlice(r, 0);

    return .unrecognised;
}

fn classifyElf(r: Reader) Facts {
    const class = r.u8At(4) orelse return .{ .undecidable = .structure_out_of_range };
    const data = r.u8At(5) orelse return .{ .undecidable = .structure_out_of_range };
    const class64 = switch (class) {
        1 => false,
        2 => true,
        else => return .unrecognised,
    };
    const endian: std.builtin.Endian = switch (data) {
        1 => .little,
        2 => .big,
        else => return .unrecognised,
    };

    const phoff: u64 = if (class64)
        (r.u64At(0x20, endian) orelse return .{ .undecidable = .structure_out_of_range })
    else
        (r.u32At(0x1c, endian) orelse return .{ .undecidable = .structure_out_of_range });
    const phentsize = (if (class64) r.u16At(0x36, endian) else r.u16At(0x2a, endian)) orelse
        return .{ .undecidable = .structure_out_of_range };
    const phnum = (if (class64) r.u16At(0x38, endian) else r.u16At(0x2c, endian)) orelse
        return .{ .undecidable = .structure_out_of_range };

    if (phnum > max_program_headers) return .{ .undecidable = .structure_out_of_range };
    if (phentsize < 4) return .{ .undecidable = .structure_out_of_range };

    const pt_interp: u32 = 3;
    var i: u16 = 0;
    while (i < phnum) : (i += 1) {
        const off = std.math.add(u64, phoff, @as(u64, i) * phentsize) catch
            return .{ .undecidable = .structure_out_of_range };
        const p_type = r.u32At(off, endian) orelse
            return .{ .undecidable = .structure_out_of_range };
        if (p_type == pt_interp)
            return .{ .elf = .{ .has_interp = true, .class64 = class64 } };
    }
    return .{ .elf = .{ .has_interp = false, .class64 = class64 } };
}

fn hostCpuType() i32 {
    return switch (builtin.cpu.arch) {
        .aarch64 => cpu_type_arm64,
        .x86_64 => cpu_type_x86_64,
        else => 0,
    };
}

/// Not requiring a subtype match is what makes the common case work: `/usr/bin/true` on
/// this machine is x86_64 + **arm64e**, and an arm64 host demanding an exact subtype
/// would find no slice and report "could not measure" for the very file the macOS CI
/// leg names.
///
/// Not *using* the subtype to break a tie is the other half, and it is deliberate.
/// arm64 and arm64e share a CPU type, so a binary carrying both leaves two candidates,
/// and which one the kernel takes depends on the grading it applies to the running
/// process — not on a rule this module can restate without inventing it. Two candidates
/// is therefore `slice_not_unique`: an answer about which slice was measured is worth
/// nothing if the slice was picked by a guess.
fn classifyFat(r: Reader, is64: bool) Facts {
    const want = hostCpuType();
    if (want == 0) return .{ .undecidable = .slice_not_unique };

    const nfat = r.u32At(4, .big) orelse return .{ .undecidable = .structure_out_of_range };
    if (nfat > max_fat_arch) return .{ .undecidable = .structure_out_of_range };

    const entry_size: u64 = if (is64) 32 else 20;
    var chosen: ?u64 = null;
    var matches: u32 = 0;
    var i: u32 = 0;
    while (i < nfat) : (i += 1) {
        const base = std.math.add(u64, 8, @as(u64, i) * entry_size) catch
            return .{ .undecidable = .structure_out_of_range };
        const cputype: i32 = @bitCast(r.u32At(base, .big) orelse
            return .{ .undecidable = .structure_out_of_range });
        if (cputype != want) continue;
        const off: u64 = if (is64)
            (r.u64At(base + 8, .big) orelse return .{ .undecidable = .structure_out_of_range })
        else
            (r.u32At(base + 8, .big) orelse return .{ .undecidable = .structure_out_of_range });
        matches += 1;
        if (chosen == null) chosen = off;
    }

    if (matches == 0) return .{ .undecidable = .slice_not_unique };
    if (matches > 1) return .{ .undecidable = .slice_not_unique };
    return classifyMachOSlice(r, chosen.?);
}

fn classifyMachOSlice(r: Reader, base: u64) Facts {
    const raw = r.u32At(base, .little) orelse return .{ .undecidable = .structure_out_of_range };
    const endian: std.builtin.Endian = if (raw == std.macho.MH_MAGIC_64 or raw == std.macho.MH_MAGIC)
        .little
    else
        .big;
    const magic = r.u32At(base, endian) orelse return .{ .undecidable = .structure_out_of_range };
    const is64 = magic == std.macho.MH_MAGIC_64;
    if (!is64 and magic != std.macho.MH_MAGIC) return .unrecognised;

    const ncmds = r.u32At(base + 16, endian) orelse return .{ .undecidable = .structure_out_of_range };
    const sizeofcmds = r.u32At(base + 20, endian) orelse return .{ .undecidable = .structure_out_of_range };
    const flags = r.u32At(base + 24, endian) orelse return .{ .undecidable = .structure_out_of_range };
    if (ncmds > max_load_commands or sizeofcmds > max_sizeofcmds)
        return .{ .undecidable = .structure_out_of_range };

    const dyldlink = flags & std.macho.MH_DYLDLINK != 0;
    const header_size: u64 = if (is64) 32 else 28;

    var off = std.math.add(u64, base, header_size) catch
        return .{ .undecidable = .structure_out_of_range };
    const limit = std.math.add(u64, off, sizeofcmds) catch
        return .{ .undecidable = .structure_out_of_range };

    var sig_cmd: ?u64 = null;
    var i: u32 = 0;
    while (i < ncmds) : (i += 1) {
        if (off >= limit) break;
        const cmd = r.u32At(off, endian) orelse return .{ .undecidable = .structure_out_of_range };
        const cmdsize = r.u32At(off + 4, endian) orelse return .{ .undecidable = .structure_out_of_range };
        if (cmdsize < 8 or cmdsize % 4 != 0) return .{ .undecidable = .structure_out_of_range };

        const cmd_end = std.math.add(u64, off, cmdsize) catch
            return .{ .undecidable = .structure_out_of_range };
        if (cmd_end > limit) return .{ .undecidable = .structure_out_of_range };

        if (cmd == @intFromEnum(std.macho.LC.CODE_SIGNATURE)) {
            if (cmdsize < 16) return .{ .undecidable = .structure_out_of_range };
            if (sig_cmd == null) sig_cmd = off;
        }
        off = cmd_end;
    }
    if (i < ncmds) return .{ .undecidable = .structure_out_of_range };

    const cmd_off = sig_cmd orelse return .{ .macho = .{ .dyldlink = dyldlink, .signing = null } };
    const dataoff = r.u32At(cmd_off + 8, endian) orelse
        return .{ .undecidable = .structure_out_of_range };
    const datasize = r.u32At(cmd_off + 12, endian) orelse
        return .{ .undecidable = .structure_out_of_range };
    const sig_at = std.math.add(u64, base, dataoff) catch
        return .{ .undecidable = .structure_out_of_range };
    const sig_end = std.math.add(u64, sig_at, datasize) catch
        return .{ .undecidable = .structure_out_of_range };
    return switch (readSigning(r, sig_at, sig_end)) {
        .ok => |s| .{ .macho = .{ .dyldlink = dyldlink, .signing = s } },
        .none => .{ .macho = .{ .dyldlink = dyldlink, .signing = null } },
        .undecidable => |u| .{ .undecidable = u },
    };
}

const SigResult = union(enum) { ok: Signing, none, undecidable: Undecidable };

fn readSigning(r: Reader, at: u64, hi: u64) SigResult {
    if (hi <= at) return .{ .undecidable = .structure_out_of_range };
    const inside = struct {
        fn f(lo: u64, end: u64, off: u64, len: u64) bool {
            const fin = std.math.add(u64, off, len) catch return false;
            return off >= lo and fin <= end;
        }
    }.f;

    if (!inside(at, hi, at, 12)) return .{ .undecidable = .structure_out_of_range };
    const magic = r.u32At(at, .big) orelse return .{ .undecidable = .structure_out_of_range };
    if (magic != std.macho.CSMAGIC_EMBEDDED_SIGNATURE) return .none;

    const super_len = r.u32At(at + 4, .big) orelse return .{ .undecidable = .structure_out_of_range };
    const super_end = std.math.add(u64, at, super_len) catch
        return .{ .undecidable = .structure_out_of_range };
    if (super_end > hi) return .{ .undecidable = .structure_out_of_range };

    const count = r.u32At(at + 8, .big) orelse return .{ .undecidable = .structure_out_of_range };
    if (count > max_superblob_entries) return .{ .undecidable = .structure_out_of_range };
    if (!inside(at, super_end, at + 12, @as(u64, count) * 8))
        return .{ .undecidable = .structure_out_of_range };

    var found: ?Signing = null;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const idx = at + 12 + @as(u64, i) * 8;
        const blob_off = r.u32At(idx + 4, .big) orelse
            return .{ .undecidable = .structure_out_of_range };
        const blob_at = std.math.add(u64, at, blob_off) catch
            return .{ .undecidable = .structure_out_of_range };
        if (!inside(at, super_end, blob_at, 8)) return .{ .undecidable = .structure_out_of_range };

        const bmagic = r.u32At(blob_at, .big) orelse
            return .{ .undecidable = .structure_out_of_range };
        if (bmagic != std.macho.CSMAGIC_CODEDIRECTORY) continue;

        const blob_len = r.u32At(blob_at + 4, .big) orelse
            return .{ .undecidable = .structure_out_of_range };
        const blob_end = std.math.add(u64, blob_at, blob_len) catch
            return .{ .undecidable = .structure_out_of_range };
        if (blob_end > super_end) return .{ .undecidable = .structure_out_of_range };
        if (!inside(blob_at, blob_end, blob_at + 12, 4) or !inside(blob_at, blob_end, blob_at + 38, 1))
            return .{ .undecidable = .structure_out_of_range };

        const flags = r.u32At(blob_at + 12, .big) orelse
            return .{ .undecidable = .structure_out_of_range };
        const platform = r.u8At(blob_at + 38) orelse
            return .{ .undecidable = .structure_out_of_range };
        const s: Signing = .{ .flags = flags, .platform = platform };

        if (found) |prev| {
            if (prev.flags != s.flags or prev.platform != s.platform)
                return .{ .undecidable = .code_directories_disagree };
        } else found = s;
    }

    if (found) |s| return .{ .ok = s };
    return .none;
}

const testing = std.testing;

fn buildMachO(a: std.mem.Allocator, opts: struct {
    flags: u32 = 0,
    platform: u8 = 0,
    mh_flags: u32 = std.macho.MH_DYLDLINK,
    cd_magic: u32 = std.macho.CSMAGIC_CODEDIRECTORY,
    super_magic: u32 = std.macho.CSMAGIC_EMBEDDED_SIGNATURE,
    second_cd: ?struct { flags: u32, platform: u8 } = null,
    ncmds_override: ?u32 = null,
    datasize_override: ?u32 = null,
    super_len_override: ?u32 = null,
    cd_len_override: ?u32 = null,
    cmdsize_override: ?u32 = null,
}) ![]u8 {
    const header_size = 32;
    const lc_size = 16;
    const sig_at: u32 = header_size + lc_size;
    const entries: u32 = if (opts.second_cd == null) 1 else 2;
    const index_size = 12 + entries * 8;
    const cd_size: u32 = 64;

    var buf = try a.alloc(u8, sig_at + index_size + entries * cd_size);
    @memset(buf, 0);

    std.mem.writeInt(u32, buf[0..4], std.macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, buf[4..8], @bitCast(hostCpuType()), .little);
    std.mem.writeInt(u32, buf[16..20], opts.ncmds_override orelse 1, .little);
    std.mem.writeInt(u32, buf[20..24], lc_size, .little);
    std.mem.writeInt(u32, buf[24..28], opts.mh_flags, .little);

    std.mem.writeInt(u32, buf[32..36], @intFromEnum(std.macho.LC.CODE_SIGNATURE), .little);
    std.mem.writeInt(u32, buf[36..40], opts.cmdsize_override orelse lc_size, .little);
    std.mem.writeInt(u32, buf[40..44], sig_at, .little);
    std.mem.writeInt(u32, buf[44..48], opts.datasize_override orelse @as(u32, @intCast(index_size + entries * cd_size)), .little);

    std.mem.writeInt(u32, buf[sig_at..][0..4], opts.super_magic, .big);
    std.mem.writeInt(u32, buf[sig_at + 4 ..][0..4], opts.super_len_override orelse @as(u32, @intCast(index_size + entries * cd_size)), .big);
    std.mem.writeInt(u32, buf[sig_at + 8 ..][0..4], entries, .big);

    var e: u32 = 0;
    while (e < entries) : (e += 1) {
        const cd_off = index_size + e * cd_size;
        std.mem.writeInt(u32, buf[sig_at + 12 + e * 8 ..][0..4], 0, .big);
        std.mem.writeInt(u32, buf[sig_at + 16 + e * 8 ..][0..4], cd_off, .big);

        const cd = sig_at + cd_off;
        std.mem.writeInt(u32, buf[cd..][0..4], opts.cd_magic, .big);
        std.mem.writeInt(u32, buf[cd + 4 ..][0..4], opts.cd_len_override orelse cd_size, .big);
        const f = if (e == 0) opts.flags else opts.second_cd.?.flags;
        const p = if (e == 0) opts.platform else opts.second_cd.?.platform;
        std.mem.writeInt(u32, buf[cd + 12 ..][0..4], f, .big);
        buf[cd + 38] = p;
    }
    return buf;
}

/// Fixtures go to a pid-unique directory. `zig build test` runs the same test in
/// several concurrent binaries, and a fixed path under /tmp passed every single run
/// before failing 66 of 80 paired runs (#28) — seen-red-once validates assertions, not
/// races, so the uniqueness is structural rather than checked.
fn fixtureDir(buf: []u8, tag: []const u8) [:0]u8 {
    const z = std.fmt.bufPrintZ(buf, "/tmp/sideeye-image-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
    _ = posix.mkdir(z.ptr, 0o755);
    return z;
}

fn writeFixture(dir: [:0]const u8, name: []const u8, bytes: []const u8, out: []u8) ![:0]u8 {
    return writeFixtureMode(dir, name, bytes, out, 0o644);
}

fn writeFixtureMode(dir: [:0]const u8, name: []const u8, bytes: []const u8, out: []u8, mode: c_uint) ![:0]u8 {
    const path = std.fmt.bufPrintZ(out, "{s}/{s}", .{ dir, name }) catch unreachable;
    const fd = posix.open(path.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, mode);
    if (fd < 0) return error.SkipZigTest;
    defer _ = posix.close(fd);
    if (bytes.len != 0) {
        const n = posix.write(fd, bytes.ptr, bytes.len);
        if (n < 0 or @as(usize, @intCast(n)) != bytes.len) return error.SkipZigTest;
    }
    return path;
}

fn buildFat(a: std.mem.Allocator, slices: []const []const u8, types: []const i32, is64: bool) ![]u8 {
    const entry: usize = if (is64) 32 else 20;
    const head = 8 + entry * slices.len;
    var total = head;
    for (slices) |sl| total += sl.len;

    var buf = try a.alloc(u8, total);
    @memset(buf, 0);
    std.mem.writeInt(u32, buf[0..4], if (is64) std.macho.FAT_MAGIC_64 else std.macho.FAT_MAGIC, .big);
    std.mem.writeInt(u32, buf[4..8], @intCast(slices.len), .big);

    var off = head;
    for (slices, types, 0..) |sl, ty, i| {
        const e = 8 + entry * i;
        std.mem.writeInt(u32, buf[e..][0..4], @bitCast(ty), .big);
        if (is64) {
            std.mem.writeInt(u64, buf[e + 8 ..][0..8], off, .big);
            std.mem.writeInt(u64, buf[e + 16 ..][0..8], sl.len, .big);
        } else {
            std.mem.writeInt(u32, buf[e + 8 ..][0..4], @intCast(off), .big);
            std.mem.writeInt(u32, buf[e + 12 ..][0..4], @intCast(sl.len), .big);
        }
        @memcpy(buf[off..][0..sl.len], sl);
        off += sl.len;
    }
    return buf;
}

fn factsOfBytes(tag: []const u8, bytes: []const u8) !Facts {
    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, tag);
    var pbuf: [512]u8 = undefined;
    const path = try writeFixture(dir, "img", bytes, &pbuf);
    defer {
        _ = posix.unlink(path.ptr);
        _ = posix.rmdir(dir.ptr);
    }
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    return observe(arena.allocator(), path, null, null).facts;
}

test "the platform byte is read even when flags are zero" {
    const bytes = try buildMachO(testing.allocator, .{ .flags = 0, .platform = 16 });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("plat", bytes);
    try testing.expect(facts == .macho);
    const s = facts.macho.signing.?;
    try testing.expectEqual(@as(u32, 0), s.flags);
    try testing.expect(s.platformNamed());
    try testing.expect(!s.libraryValidation());
}

test "library validation is read from flags" {
    const bytes = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("libval", bytes);
    const s = facts.macho.signing.?;
    try testing.expect(s.libraryValidation());
    try testing.expect(!s.platformNamed());
    try testing.expect(!s.hardenedRuntime());
}

test "adhoc and linker-signed are distinguished from a blocking flag" {
    const bytes = try buildMachO(testing.allocator, .{ .flags = cs_adhoc | cs_linker_signed });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("adhoc", bytes);
    const s = facts.macho.signing.?;
    try testing.expectEqual(cs_adhoc | cs_linker_signed, s.flags);
    try testing.expect(!s.libraryValidation() and !s.hardenedRuntime() and !s.platformNamed());
}

test "code directories that disagree are undecidable, not first-wins" {
    const bytes = try buildMachO(testing.allocator, .{
        .flags = cs_require_lv,
        .second_cd = .{ .flags = 0, .platform = 16 },
    });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("disagree", bytes);
    try testing.expectEqual(Facts{ .undecidable = .code_directories_disagree }, facts);
}

test "code directories that agree are not undecidable" {
    const bytes = try buildMachO(testing.allocator, .{
        .flags = cs_require_lv,
        .second_cd = .{ .flags = cs_require_lv, .platform = 0 },
    });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("agree", bytes);
    try testing.expect(facts == .macho);
    try testing.expect(facts.macho.signing.?.libraryValidation());
}

test "a declared load-command count past the cap is undecidable, not a partial read" {
    const bytes = try buildMachO(testing.allocator, .{ .ncmds_override = max_load_commands + 1 });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("ncmds", bytes);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, facts);
}

test "a superblob that is not a signature reads as unsigned" {
    const bytes = try buildMachO(testing.allocator, .{ .super_magic = 0xdeadbeef });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("supermagic", bytes);
    try testing.expect(facts == .macho);
    try testing.expect(facts.macho.signing == null);
}

test "a blob that is not a code directory is skipped, not read as one" {
    const bytes = try buildMachO(testing.allocator, .{ .cd_magic = 0xfade0b01, .flags = cs_require_lv });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("blobmagic", bytes);
    try testing.expect(facts == .macho);
    try testing.expect(facts.macho.signing == null);
}

test "a field that runs past the end of the file is out of range, not a default" {
    // the code directory, so a tail cut removes nothing either read touches. A
    // truncation test has to cut where the parser actually looks, or it passes for a
    // reason unrelated to the bounds check it claims to hold.
    const full = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .platform = 16 });
    defer testing.allocator.free(full);

    // Laid out the way buildMachO does: mach header, one load command, the superblob
    // head and its single index entry.
    const cd_at: usize = 32 + 16 + 12 + 8;

    const cut_platform = try factsOfBytes("cut-platform", full[0 .. cd_at + 38]);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, cut_platform);

    const cut_flags = try factsOfBytes("cut-flags", full[0 .. cd_at + 12]);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, cut_flags);

    // The control: the untouched fixture reads both fields, so the two refusals above
    // are the cut and not something the fixture always did.
    const whole = try factsOfBytes("cut-none", full);
    try testing.expect(whole.macho.signing.?.libraryValidation());
    try testing.expect(whole.macho.signing.?.platformNamed());
}

test "a universal binary is read through the slice matching this CPU" {
    const lv = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(lv);
    const plain = try buildMachO(testing.allocator, .{ .flags = 0, .platform = 16 });
    defer testing.allocator.free(plain);

    // The foreign slice is placed first and carries the opposite answer, so a reader
    // that takes slice zero rather than the matching one reports `platform` where the
    // host's slice says library validation.
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;
    const fat = try buildFat(testing.allocator, &.{ plain, lv }, &.{ other, hostCpuType() }, false);
    defer testing.allocator.free(fat);

    const facts = try factsOfBytes("fat-pick", fat);
    try testing.expect(facts.macho.signing.?.libraryValidation());
    try testing.expect(!facts.macho.signing.?.platformNamed());
}

test "FAT64 offsets are read as 64-bit, not as the low half of a 32-bit field" {
    const lv = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(lv);
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;
    const plain = try buildMachO(testing.allocator, .{ .flags = 0 });
    defer testing.allocator.free(plain);

    const fat = try buildFat(testing.allocator, &.{ plain, lv }, &.{ other, hostCpuType() }, true);
    defer testing.allocator.free(fat);
    const facts = try factsOfBytes("fat64", fat);
    try testing.expect(facts.macho.signing.?.libraryValidation());
}

test "two slices sharing this CPU type are undecidable, not first-wins" {
    const a1 = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(a1);
    const a2 = try buildMachO(testing.allocator, .{ .flags = 0, .platform = 16 });
    defer testing.allocator.free(a2);

    const fat = try buildFat(testing.allocator, &.{ a1, a2 }, &.{ hostCpuType(), hostCpuType() }, false);
    defer testing.allocator.free(fat);
    const facts = try factsOfBytes("fat-tie", fat);
    try testing.expectEqual(Facts{ .undecidable = .slice_not_unique }, facts);
}

test "a universal binary carrying no slice for this CPU says so" {
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;
    const plain = try buildMachO(testing.allocator, .{ .flags = 0 });
    defer testing.allocator.free(plain);
    const fat = try buildFat(testing.allocator, &.{plain}, &.{other}, false);
    defer testing.allocator.free(fat);
    const facts = try factsOfBytes("fat-none", fat);
    try testing.expectEqual(Facts{ .undecidable = .slice_not_unique }, facts);
}

test "the declared lengths bound the read, one field at a time" {
    // Each case drives exactly one declared length and leaves the bytes where they were,
    // so the refusal is attributable to that field rather than to the shape collapsing.
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .datasize_override = 0 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-datasize", b));
    }
    // `datasize` non-zero but smaller than the SuperBlob claims for itself. This is the
    // case that pins `datasize` specifically: with zero, the region is empty and the
    // emptiness check refuses before the SuperBlob's length is ever compared, so a build
    // that ignored `datasize` entirely still passed the case above.
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .datasize_override = 16 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-datasize-short", b));
    }
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .super_len_override = 1 << 20 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-super", b));
    }
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .cd_len_override = 8 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-cd", b));
    }
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .cmdsize_override = 1 << 16 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-cmdsize", b));
    }
    // The control: the same fixture with every length as built reads both fields, so the
    // four refusals above are the overrides and not something the fixture always did.
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .platform = 16 });
        defer testing.allocator.free(b);
        const f = try factsOfBytes("len-control", b);
        try testing.expect(f.macho.signing.?.libraryValidation());
        try testing.expect(f.macho.signing.?.platformNamed());
    }
}

test "a header counting more commands than its span holds refuses, signature or not" {
    // first round of bounds fixes. The signature being *valid* is the point of the
    // fixture: a malformed one would refuse for an unrelated reason and the test would
    // pass without covering anything.
    const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .ncmds_override = 2 });
    defer testing.allocator.free(b);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("ncmds-span", b));

    // The control: the same bytes with an honest count read the signature, so the
    // refusal above is the disagreement and not the fixture.
    const ok = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(ok);
    const f = try factsOfBytes("ncmds-span-control", ok);
    try testing.expect(f.macho.signing.?.libraryValidation());
}

test "a fat header declaring more slices than the cap is undecidable" {
    // The file has to be large enough that all the declared entries are readable.
    // A first version of this test raised `nfat_arch` on a small fixture, and it passed
    // whether the cap existed or not: the entries ran off the end and the bounds check
    // refused first, so the cap itself was never the reason. A guard whose test passes
    // for another guard's reason is not tested at all.
    const n = max_fat_arch + 1;
    const body = try testing.allocator.alloc(u8, 8 + n * 20 + 64);
    defer testing.allocator.free(body);
    @memset(body, 0);
    std.mem.writeInt(u32, body[0..4], std.macho.FAT_MAGIC, .big);
    std.mem.writeInt(u32, body[4..8], n, .big);
    // Entries left as zeros: a cputype of 0 matches no host, so *without* the cap this
    // walks all of them and answers `slice_not_unique`. With the cap it refuses on the
    // count. The two outcomes differ, which is what makes the cap falsifiable here.
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("fat-cap", body));
}

test "hostile bytes produce an answer, never a crash" {
    const thin = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .platform = 16 });
    defer testing.allocator.free(thin);
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;

    const fat32 = try buildFat(testing.allocator, &.{ thin, thin }, &.{ other, hostCpuType() }, false);
    defer testing.allocator.free(fat32);
    const fat64 = try buildFat(testing.allocator, &.{ thin, thin }, &.{ other, hostCpuType() }, true);
    defer testing.allocator.free(fat64);

    const fixtures = [_][]const u8{
        thin,
        fat32,
        fat64,
        try buildElf(testing.allocator, .{}),
    };
    defer testing.allocator.free(fixtures[3]);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, "hostile");
    var pbuf: [512]u8 = undefined;
    defer _ = posix.rmdir(dir.ptr);

    const scratch = try testing.allocator.alloc(u8, 8192);
    defer testing.allocator.free(scratch);

    for (fixtures) |fixture| {
        var cut: usize = 0;
        while (cut <= fixture.len) : (cut += 1) {
            const path = try writeFixture(dir, "h", fixture[0..cut], &pbuf);
            _ = observe(arena.allocator(), path, null, null);
            _ = posix.unlink(path.ptr);
        }
        for ([_]u8{ 0xff, 0x00 }) |fill| {
            var i: usize = 0;
            while (i < fixture.len) : (i += 1) {
                @memcpy(scratch[0..fixture.len], fixture);
                scratch[i] = fill;
                const path = try writeFixture(dir, "h", scratch[0..fixture.len], &pbuf);
                _ = observe(arena.allocator(), path, null, null);
                _ = posix.unlink(path.ptr);
            }
        }
    }
}

fn buildElf(a: std.mem.Allocator, opts: struct {
    class64: bool = true,
    endian: std.builtin.Endian = .little,
    interp: bool = true,
    phnum_override: ?u16 = null,
}) ![]u8 {
    const ehsize: usize = if (opts.class64) 64 else 52;
    const phentsize: usize = if (opts.class64) 56 else 32;
    var buf = try a.alloc(u8, ehsize + phentsize);
    @memset(buf, 0);
    @memcpy(buf[0..4], "\x7fELF");
    buf[4] = if (opts.class64) 2 else 1;
    buf[5] = if (opts.endian == .little) 1 else 2;

    const phnum: u16 = opts.phnum_override orelse 1;
    if (opts.class64) {
        std.mem.writeInt(u64, buf[0x20..0x28], ehsize, opts.endian);
        std.mem.writeInt(u16, buf[0x36..0x38], @intCast(phentsize), opts.endian);
        std.mem.writeInt(u16, buf[0x38..0x3a], phnum, opts.endian);
    } else {
        std.mem.writeInt(u32, buf[0x1c..0x20], @intCast(ehsize), opts.endian);
        std.mem.writeInt(u16, buf[0x2a..0x2c], @intCast(phentsize), opts.endian);
        std.mem.writeInt(u16, buf[0x2c..0x2e], phnum, opts.endian);
    }
    std.mem.writeInt(u32, buf[ehsize..][0..4], if (opts.interp) 3 else 1, opts.endian);
    return buf;
}

test "PT_INTERP decides dynamic against static, on both classes and both endians" {
    // Four combinations because the header offsets differ by class and every field is
    // read with an explicit endianness; a struct cast would pass one and fail three.
    for ([_]bool{ true, false }) |class64| {
        for ([_]std.builtin.Endian{ .little, .big }) |endian| {
            const dyn = try buildElf(testing.allocator, .{ .class64 = class64, .endian = endian, .interp = true });
            defer testing.allocator.free(dyn);
            const dyn_facts = try factsOfBytes("elf-dyn", dyn);
            try testing.expect(dyn_facts.elf.has_interp);
            try testing.expectEqual(class64, dyn_facts.elf.class64);

            const stat = try buildElf(testing.allocator, .{ .class64 = class64, .endian = endian, .interp = false });
            defer testing.allocator.free(stat);
            const stat_facts = try factsOfBytes("elf-static", stat);
            try testing.expect(!stat_facts.elf.has_interp);
        }
    }
}

test "an ELF program-header count past the cap is undecidable" {
    const bytes = try buildElf(testing.allocator, .{ .phnum_override = max_program_headers + 1 });
    defer testing.allocator.free(bytes);
    const facts = try factsOfBytes("elf-phcap", bytes);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, facts);
}

test "a script is unrecognised rather than guessed at" {
    const facts = try factsOfBytes("script", "#!/bin/sh\necho hi\n");
    try testing.expectEqual(Facts.unrecognised, facts);
}

test "argv[0] without a slash is not resolved, and says so" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const obs = observe(arena.allocator(), "git", null, null);
    try testing.expectEqual(Facts{ .not_resolved = .path_unset }, obs.facts);
    try testing.expect(obs.path == null);
    try testing.expect(obs.size == null);
    try testing.expect(!obs.via_path);
}

test "searchPath takes the first executable regular file, as execvp would (ADR 0090)" {
    var rbuf: [256]u8 = undefined;
    const root = fixtureDir(&rbuf, "search");
    var b1: [320]u8 = undefined;
    var b2: [320]u8 = undefined;
    var b3: [320]u8 = undefined;
    var b4: [320]u8 = undefined;
    const a = try std.fmt.bufPrintZ(&b1, "{s}/a", .{root});
    const b = try std.fmt.bufPrintZ(&b2, "{s}/b", .{root});
    const c = try std.fmt.bufPrintZ(&b3, "{s}/c", .{root});
    const a_tool = try std.fmt.bufPrintZ(&b4, "{s}/a/tool", .{root});
    _ = posix.mkdir(a.ptr, 0o755);
    _ = posix.mkdir(b.ptr, 0o755);
    _ = posix.mkdir(c.ptr, 0o755);
    _ = posix.mkdir(a_tool.ptr, 0o755);
    var pb: [512]u8 = undefined;
    var pc: [512]u8 = undefined;
    const b_tool = try writeFixtureMode(b, "tool", "x", &pb, 0o644);
    const c_tool = try writeFixtureMode(c, "tool", "x", &pc, 0o755);
    defer {
        _ = posix.unlink(b_tool.ptr);
        _ = posix.unlink(c_tool.ptr);
        _ = posix.rmdir(a_tool.ptr);
        _ = posix.rmdir(a.ptr);
        _ = posix.rmdir(b.ptr);
        _ = posix.rmdir(c.ptr);
        _ = posix.rmdir(root.ptr);
    }

    var out: [search_path_max]u8 = undefined;
    var env_buf: [1024]u8 = undefined;
    const env = try std.fmt.bufPrint(&env_buf, "{s}:{s}:{s}", .{ a, b, c });
    try testing.expectEqualStrings(c_tool, searchPath(&out, "tool", env, null) orelse return error.TestUnexpectedResult);
    const env_c_first = try std.fmt.bufPrint(&env_buf, "{s}:{s}", .{ c, b });
    try testing.expectEqualStrings(c_tool, searchPath(&out, "tool", env_c_first, null) orelse return error.TestUnexpectedResult);
    // Control: without c nothing qualifies, so the directory and the non-executable file
    // are what the first assertion walked past, not what it happened to miss.
    const env_no_c = try std.fmt.bufPrint(&env_buf, "{s}:{s}", .{ a, b });
    try testing.expect(searchPath(&out, "tool", env_no_c, null) == null);

    var want: [512]u8 = undefined;
    try testing.expectEqualStrings(
        try std.fmt.bufPrint(&want, "{s}/c/tool", .{root}),
        searchPath(&out, "tool", "c", root) orelse return error.TestUnexpectedResult,
    );
    try testing.expectEqualStrings(
        try std.fmt.bufPrint(&want, "{s}/./tool", .{c}),
        searchPath(&out, "tool", "/nonexistent-for-this-test::", c) orelse return error.TestUnexpectedResult,
    );
    try testing.expect(searchPath(&out, "tool", "c", a) == null);
}

test "startable says which of missing, not a regular file, no execute bit, or off PATH (#701)" {
    var as = std.heap.ArenaAllocator.init(testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    var rbuf: [256]u8 = undefined;
    const root = fixtureDir(&rbuf, "start");
    var pd: [320]u8 = undefined;
    const dir = try std.fmt.bufPrintZ(&pd, "{s}/d", .{root});
    _ = posix.mkdir(dir.ptr, 0o755);
    var p1: [512]u8 = undefined;
    var p2: [512]u8 = undefined;
    var p3: [512]u8 = undefined;
    var p4: [512]u8 = undefined;
    var p5: [512]u8 = undefined;
    var p6: [512]u8 = undefined;
    var p7: [512]u8 = undefined;
    var p8: [512]u8 = undefined;
    const prog = try writeFixtureMode(root, "prog", "x", &p1, 0o755);
    const plain = try writeFixtureMode(root, "plain", "x", &p2, 0o644);
    const bad_interp = try writeFixtureMode(root, "bad", "#!/nonexistent-interpreter-for-701 -x\necho\n", &p3, 0o755);
    const good_interp = try writeFixtureMode(root, "good", "#!/bin/sh\necho\n", &p4, 0o755);
    const crlf = try writeFixtureMode(root, "crlf", "#!/bin/sh\r\necho\r\n", &p5, 0o755);
    const env_missing = try writeFixtureMode(root, "envmiss", "#!/usr/bin/env no-such-name-for-701\n", &p6, 0o755);
    const env_found = try writeFixtureMode(root, "envfound", "#!/usr/bin/env prog\n", &p7, 0o755);
    const env_two = try writeFixtureMode(root, "envtwo", "#!/usr/bin/env no-such-name-for-701 -u\n", &p8, 0o755);
    defer {
        for ([_][:0]u8{ prog, plain, bad_interp, good_interp, crlf, env_missing, env_found, env_two }) |p| _ = posix.unlink(p.ptr);
        _ = posix.rmdir(dir.ptr);
        _ = posix.rmdir(root.ptr);
    }
    if (posix.access("/usr/bin/env", posix.X_OK) != 0) return error.SkipZigTest;

    try testing.expect(startable(a, prog, null, null).fault == .ok);
    var mb: [512]u8 = undefined;
    const absent = try std.fmt.bufPrint(&mb, "{s}/absent", .{root});
    const m = startable(a, absent, null, null);
    try testing.expect(m.fault == .missing);
    try testing.expectEqualStrings(absent, m.file.?);
    try testing.expect(startable(a, plain, null, null).fault == .no_exec_bit);
    try testing.expect(startable(a, dir, null, null).fault == .not_regular);
    var nb: [512]u8 = undefined;
    try testing.expect(startable(a, try std.fmt.bufPrint(&nb, "{s}/x", .{plain}), null, null).fault == .missing);
    const rel = startable(a, "./plain", root, null);
    try testing.expect(rel.fault == .no_exec_bit);
    try testing.expect(std.mem.endsWith(u8, rel.file.?, "/plain"));

    const bi = startable(a, bad_interp, null, null);
    try testing.expect(bi.fault == .missing);
    try testing.expectEqualStrings("/nonexistent-interpreter-for-701", bi.interpreter.?);
    try testing.expectEqualStrings(bad_interp, bi.file.?);
    try testing.expect(startable(a, good_interp, null, null).fault == .ok);
    const cr = startable(a, crlf, null, null);
    try testing.expect(cr.fault == .missing);
    try testing.expectEqualStrings("/bin/sh\r", cr.interpreter.?);
    const em = startable(a, env_missing, null, root);
    try testing.expect(em.fault == .not_on_path);
    try testing.expectEqualStrings("no-such-name-for-701", em.name.?);
    try testing.expectEqualStrings("/usr/bin/env", em.interpreter.?);
    try testing.expect(startable(a, env_found, null, root).fault == .ok);
    try testing.expect(startable(a, env_two, null, root).fault == .ok);
    try testing.expect(startable(a, env_missing, null, null).fault == .ok);

    const off = startable(a, "no-such-name-for-701", null, root);
    try testing.expect(off.fault == .not_on_path);
    try testing.expectEqualStrings("no-such-name-for-701", off.name.?);
    try testing.expect(off.file == null);
    try testing.expectEqualStrings(prog, startable(a, "prog", null, root).file.?);
    // Control for the row above: `plain` is on the same PATH and is not executable, so the
    // search walks past it — the answer is "not on PATH", as execvp would fail.
    try testing.expect(startable(a, "plain", null, root).fault == .not_on_path);
    try testing.expect(startable(a, "prog", null, null).fault == .not_judged);
    try testing.expect(startable(a, "", null, root).fault == .not_judged);
}

test "a bare name passes when execvp would reach a later candidate past a broken #! (#701 review)" {
    var as = std.heap.ArenaAllocator.init(testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    var rbuf: [256]u8 = undefined;
    const root = fixtureDir(&rbuf, "start-path");
    var b1: [320]u8 = undefined;
    var b2: [320]u8 = undefined;
    const d1 = try std.fmt.bufPrintZ(&b1, "{s}/one", .{root});
    const d2 = try std.fmt.bufPrintZ(&b2, "{s}/two", .{root});
    _ = posix.mkdir(d1.ptr, 0o755);
    _ = posix.mkdir(d2.ptr, 0o755);
    var p1: [512]u8 = undefined;
    var p2: [512]u8 = undefined;
    var p3: [512]u8 = undefined;
    var p4: [512]u8 = undefined;
    const broken = try writeFixtureMode(d1, "tool", "#!/nonexistent-interpreter-for-701\n", &p1, 0o755);
    const good = try writeFixtureMode(d2, "tool", "#!/bin/sh\necho\n", &p2, 0o755);
    const env_first = try writeFixtureMode(d1, "envtool", "#!/usr/bin/env no-such-name-for-701\n", &p3, 0o755);
    const env_later = try writeFixtureMode(d2, "envtool", "#!/bin/sh\necho\n", &p4, 0o755);
    defer {
        for ([_][:0]u8{ broken, good, env_first, env_later }) |p| _ = posix.unlink(p.ptr);
        _ = posix.rmdir(d1.ptr);
        _ = posix.rmdir(d2.ptr);
        _ = posix.rmdir(root.ptr);
    }
    if (posix.access("/usr/bin/env", posix.X_OK) != 0) return error.SkipZigTest;
    var eb: [700]u8 = undefined;
    const both = try std.fmt.bufPrint(&eb, "{s}:{s}", .{ d1, d2 });
    const s = startable(a, "tool", null, both);
    try testing.expect(s.fault == .ok);
    try testing.expectEqualStrings(good, s.file.?);
    // Control: with the good directory off PATH, the broken first candidate is the answer.
    const only = startable(a, "tool", null, d1);
    try testing.expect(only.fault == .missing);
    try testing.expectEqualStrings("/nonexistent-interpreter-for-701", only.interpreter.?);
    const e = startable(a, "envtool", null, both);
    try testing.expect(e.fault == .not_on_path);
    try testing.expectEqualStrings(env_first, e.file.?);
}

test "a bare argv[0] is read off PATH and says it was, or says why it was not" {
    var rbuf: [256]u8 = undefined;
    const dir = fixtureDir(&rbuf, "bare");
    var pbuf: [512]u8 = undefined;
    const path = try writeFixtureMode(dir, "prog", "#!/bin/sh\n", &pbuf, 0o755);
    defer {
        _ = posix.unlink(path.ptr);
        _ = posix.rmdir(dir.ptr);
    }
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const found = observe(arena.allocator(), "prog", null, dir);
    try testing.expect(found.via_path);
    try testing.expectEqualStrings(path, found.path orelse return error.TestUnexpectedResult);
    try testing.expectEqual(Facts.unrecognised, found.facts);
    try testing.expectEqual(observe(arena.allocator(), path, null, null).facts, found.facts);

    const missing = observe(arena.allocator(), "no-such-prog-for-this-test", null, dir);
    try testing.expectEqual(Facts{ .not_resolved = .not_found }, missing.facts);
    try testing.expect(missing.path == null and !missing.via_path);
}

test "a relative argv[0] resolves against the declared cwd, as the child will" {
    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, "cwd");
    const bytes = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(bytes);
    var pbuf: [512]u8 = undefined;
    const path = try writeFixture(dir, "prog", bytes, &pbuf);
    defer {
        _ = posix.unlink(path.ptr);
        _ = posix.rmdir(dir.ptr);
    }

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The pair is the test. A resolver that ignores `cwd` still passes the positive
    // half whenever the process happens to sit in the right directory, so the negative
    // half — the same argv[0] against a directory that holds nothing — is what pins the
    // join actually happening.
    const with = observe(arena.allocator(), "./prog", dir, null);
    try testing.expect(with.facts == .macho);
    const without = observe(arena.allocator(), "./prog", "/nonexistent-cwd-for-this-test", null);
    try testing.expectEqual(Facts{ .unreadable = .no_such_file }, without.facts);
}

test "a second reading of a replaced file does not agree with the first" {
    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, "swap");
    const lv = try buildMachO(testing.allocator, .{ .flags = cs_require_lv });
    defer testing.allocator.free(lv);
    var pbuf: [512]u8 = undefined;
    const path = try writeFixture(dir, "p", lv, &pbuf);
    defer {
        _ = posix.unlink(path.ptr);
        _ = posix.rmdir(dir.ptr);
    }

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const before = observe(a, path, null, null);
    try testing.expect(before.facts.macho.signing.?.libraryValidation());
    // Same reading twice is agreement: without this half, an implementation that always
    // reports disagreement would pass the interesting half of the test.
    try testing.expect(sameAnswer(before, reobserve(a, path)));

    const plain = try buildMachO(testing.allocator, .{ .flags = 0, .platform = 16 });
    defer testing.allocator.free(plain);
    _ = try writeFixture(dir, "p", plain, &pbuf);
    try testing.expect(!sameAnswer(before, reobserve(a, path)));
}

test "the host's own binaries, as a smoke test only" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const t = observe(a, "/usr/bin/true", null, null);
    if (t.facts == .macho) {
        const s = t.facts.macho.signing.?;
        try testing.expect(s.platformNamed());
        try testing.expect(!s.libraryValidation());
    }

    // A second host file, read only to show the reader reaches a Mach-O at all. No
    // expectation is pinned on its flags: what a system binary carries is Apple's to
    // change, and the parser's own falsification is the fixtures above.
    const other = observe(a, "/bin/ls", null, null);
    try testing.expect(other.facts == .macho or other.facts == .undecidable);
}

pub const FakeFramework = struct {
    root: [:0]const u8,
    dirs: [10][:0]const u8,
    launcher: [:0]const u8,
    lib: [:0]const u8,
    interpreter: [:0]const u8,
    venv_python: [:0]const u8,
    venv_cfg: [:0]const u8,
    script: [:0]const u8,
    stray: [:0]const u8,

    pub fn remove(self: FakeFramework) void {
        for ([_][:0]const u8{ self.script, self.venv_python, self.venv_cfg, self.interpreter, self.lib, self.launcher, self.stray }) |f| _ = posix.unlink(f.ptr);
        var i: usize = self.dirs.len;
        while (i > 0) {
            i -= 1;
            _ = posix.rmdir(self.dirs[i].ptr);
        }
        _ = posix.rmdir(self.root.ptr);
    }
};

pub fn fakeFrameworkForTest(a: std.mem.Allocator, tag: []const u8) !FakeFramework {
    var dbuf: [256]u8 = undefined;
    const root = try a.dupeZ(u8, fixtureDir(&dbuf, tag));
    const rel = [_][]const u8{
        "Versions",                                          "Versions/3.99",
        "Versions/3.99/bin",                                 "Versions/3.99/Resources",
        "Versions/3.99/Resources/Python.app",                "Versions/3.99/Resources/Python.app/Contents",
        "Versions/3.99/Resources/Python.app/Contents/MacOS", "venv",
        "venv/bin",                                          "elsewhere",
    };
    var ff: FakeFramework = undefined;
    ff.root = root;
    for (rel, 0..) |r, k| {
        ff.dirs[k] = try std.fs.path.joinZ(a, &.{ root, r });
        _ = posix.mkdir(ff.dirs[k].ptr, 0o755);
    }
    var pbuf: [512]u8 = undefined;
    ff.launcher = try a.dupeZ(u8, try writeFixtureMode(ff.dirs[2], "python3.99", try buildMachO(a, .{}), &pbuf, 0o755));
    ff.lib = try a.dupeZ(u8, try writeFixture(ff.dirs[1], "Python", "not a real dylib", &pbuf));
    ff.interpreter = try a.dupeZ(u8, try writeFixtureMode(ff.dirs[6], "Python", try buildMachO(a, .{}), &pbuf, 0o755));
    ff.venv_cfg = try a.dupeZ(u8, try writeFixture(ff.dirs[7], "pyvenv.cfg", "home = x\n", &pbuf));
    ff.venv_python = try std.fs.path.joinZ(a, &.{ ff.dirs[8], "python" });
    _ = posix.unlink(ff.venv_python.ptr);
    if (posix.symlink(ff.launcher.ptr, ff.venv_python.ptr) != 0) return error.SkipZigTest;
    const shebang = try std.fmt.allocPrint(a, "#!{s} -sE\nprint('tool')\n", .{ff.venv_python});
    ff.script = try a.dupeZ(u8, try writeFixtureMode(ff.dirs[8], "tool", shebang, &pbuf, 0o755));
    ff.stray = try a.dupeZ(u8, try writeFixtureMode(ff.dirs[9], "python3", try buildMachO(a, .{}), &pbuf, 0o755));
    return ff;
}

fn realpathOf(a: std.mem.Allocator, p: []const u8) ![]const u8 {
    var buf: [search_path_max]u8 = undefined;
    const z = try a.dupeZ(u8, p);
    return a.dupe(u8, std.mem.span(posix.realpath(z.ptr, &buf) orelse return error.TestUnexpectedResult));
}

test "a framework Python's launcher names the framework's interpreter (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const ff = try fakeFrameworkForTest(a, "fw-launcher");
    defer ff.remove();

    const direct = frameworkPython(a, observePath(a, ff.launcher)) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(try realpathOf(a, ff.interpreter), try realpathOf(a, direct.interpreter));
    try testing.expectEqualStrings(ff.launcher, direct.launcher);
    try testing.expect(direct.script == null and direct.venv_launcher == null);

    const venv = frameworkPython(a, observePath(a, ff.venv_python)) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(ff.venv_python, venv.launcher);
    const want = try std.fs.path.join(a, &.{ try realpathOf(a, ff.dirs[8]), "python" });
    try testing.expectEqualStrings(want, venv.venv_launcher orelse return error.TestUnexpectedResult);

    const script = frameworkPython(a, observePath(a, ff.script)) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(ff.script, script.script orelse return error.TestUnexpectedResult);
    try testing.expectEqualStrings(ff.venv_python, script.launcher);
}

test "nothing is named where the framework's layout does not hold (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const ff = try fakeFrameworkForTest(a, "fw-negative");
    defer ff.remove();

    try testing.expect(frameworkPython(a, observePath(a, ff.stray)) == null);
    var pbuf: [512]u8 = undefined;
    const text_interp = try writeFixture(ff.dirs[9], "notanimage", "plain text\n", &pbuf);
    const text_interp_d = try a.dupeZ(u8, text_interp);
    defer _ = posix.unlink(text_interp_d.ptr);
    const bad_script = try writeFixtureMode(ff.dirs[2], "pip3", try std.fmt.allocPrint(a, "#!{s}\n", .{text_interp_d}), &pbuf, 0o755);
    const bad_script_d = try a.dupeZ(u8, bad_script);
    defer _ = posix.unlink(bad_script_d.ptr);
    try testing.expect(frameworkPython(a, observePath(a, bad_script_d)) == null);
    try testing.expect(frameworkPython(a, .{ .path = bad_script_d, .size = 0, .facts = .unrecognised }) == null);
    const config = try writeFixtureMode(ff.dirs[2], "python3.99-config", "#!/bin/sh\necho flags\n", &pbuf, 0o755);
    const config_d = try a.dupeZ(u8, config);
    defer _ = posix.unlink(config_d.ptr);
    const via_config = try writeFixtureMode(ff.dirs[9], "uses-config", try std.fmt.allocPrint(a, "#!{s}\n", .{config_d}), &pbuf, 0o755);
    const via_config_d = try a.dupeZ(u8, via_config);
    defer _ = posix.unlink(via_config_d.ptr);
    try testing.expect(frameworkPython(a, observePath(a, via_config_d)) == null);
    try testing.expect(frameworkPython(a, .{ .path = ff.launcher, .size = 0, .facts = .{ .elf = .{ .has_interp = true, .class64 = true } } }) == null);

    _ = posix.unlink(ff.interpreter.ptr);
    try testing.expect(frameworkPython(a, observePath(a, ff.launcher)) == null);
    var pbuf2: [512]u8 = undefined;
    _ = try writeFixtureMode(ff.dirs[6], "Python", try buildMachO(a, .{}), &pbuf2, 0o755);
    try testing.expect(frameworkPython(a, observePath(a, ff.launcher)) != null);
    _ = posix.unlink(ff.lib.ptr);
    try testing.expect(frameworkPython(a, observePath(a, ff.launcher)) == null);
}

test "a #! line's interpreter is its first word, when that is an absolute path (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, "shebang");
    defer _ = posix.rmdir(dir.ptr);
    const cases = [_]struct { body: []const u8, want: ?[]const u8 }{
        .{ .body = "#!/opt/x/python3 -E\nprint()\n", .want = "/opt/x/python3" },
        .{ .body = "#! \t/opt/x/python3\n", .want = "/opt/x/python3" },
        .{ .body = "#!/usr/bin/env python3\n", .want = "/usr/bin/env" },
        .{ .body = "#!python3\n", .want = null },
        .{ .body = "#!/opt/x/python3", .want = "/opt/x/python3" },
        .{ .body = "print()\n", .want = null },
    };
    for (cases) |c| {
        var pbuf: [512]u8 = undefined;
        const p = try writeFixture(dir, "s", c.body, &pbuf);
        defer _ = posix.unlink(p.ptr);
        const got = if (shebangOf(a, p)) |sb| sb.interpreter else null;
        if (c.want) |w| try testing.expectEqualStrings(w, got orelse return error.TestUnexpectedResult) else try testing.expect(got == null);
    }
}

fn bundleDirsForTest(a: std.mem.Allocator, root: []const u8, bundle: []const u8, version: []const u8) ![8][:0]const u8 {
    const v = try std.fmt.allocPrint(a, "{s}/Versions/{s}", .{ bundle, version });
    const app = try std.fmt.allocPrint(a, "{s}/Resources/Python.app", .{v});
    const rel = [8][]const u8{
        bundle,
        try std.fmt.allocPrint(a, "{s}/Versions", .{bundle}),
        v,
        try std.fmt.allocPrint(a, "{s}/bin", .{v}),
        try std.fmt.allocPrint(a, "{s}/Resources", .{v}),
        app,
        try std.fmt.allocPrint(a, "{s}/Contents", .{app}),
        try std.fmt.allocPrint(a, "{s}/Contents/MacOS", .{app}),
    };
    var dirs: [8][:0]const u8 = undefined;
    for (rel, 0..) |r, k| {
        dirs[k] = try std.fs.path.joinZ(a, &.{ root, r });
        _ = posix.mkdir(dirs[k].ptr, 0o755);
    }
    return dirs;
}

fn removeForTest(files: []const [:0]const u8, dirs: []const [:0]const u8, root: [:0]const u8) void {
    for (files) |f| _ = posix.unlink(f.ptr);
    var i: usize = dirs.len;
    while (i > 0) {
        i -= 1;
        _ = posix.rmdir(dirs[i].ptr);
    }
    _ = posix.rmdir(root.ptr);
}

test "the framework library is named after the framework, as in the Command Line Tools' Python3.framework (#703)" {
    try testing.expectEqualStrings("Python3", frameworkName("/L/Frameworks/Python3.framework/Versions/3.9"));
    try testing.expectEqualStrings("Python", frameworkName("/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14"));
    try testing.expectEqualStrings("PythonT", frameworkName("/x/PythonT.framework/Versions/3.14"));
    try testing.expectEqualStrings("Python", frameworkName("/tmp/sideeye-image-x-1/Versions/3.99"));
    try testing.expectEqualStrings("Python", frameworkName("/a/b"));

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var dbuf: [256]u8 = undefined;
    const root = try a.dupeZ(u8, fixtureDir(&dbuf, "fw-clt"));
    const dirs = try bundleDirsForTest(a, root, "Python3.framework", "3.9");
    var pbuf: [512]u8 = undefined;
    const launcher = try a.dupeZ(u8, try writeFixtureMode(dirs[3], "python3.9", try buildMachO(a, .{}), &pbuf, 0o755));
    const interp = try a.dupeZ(u8, try writeFixtureMode(dirs[7], "Python", try buildMachO(a, .{}), &pbuf, 0o755));
    const wrong = try a.dupeZ(u8, try writeFixture(dirs[2], "Python", "not this framework's library", &pbuf));
    try testing.expect(frameworkPython(a, observePath(a, launcher)) == null);
    _ = posix.unlink(wrong.ptr);
    const lib = try a.dupeZ(u8, try writeFixture(dirs[2], "Python3", "the framework's library", &pbuf));
    const fw = frameworkPython(a, observePath(a, launcher)) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(try realpathOf(a, interp), try realpathOf(a, fw.interpreter));
    removeForTest(&.{ launcher, interp, lib }, &dirs, root);
}

test "a #! line's options are carried with its interpreter (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var dbuf: [256]u8 = undefined;
    const dir = fixtureDir(&dbuf, "shebang-opts");
    defer _ = posix.rmdir(dir.ptr);
    const cases = [_]struct { body: []const u8, interp: []const u8, opts: []const u8 }{
        .{ .body = "#!/opt/x/python3 -sE\n", .interp = "/opt/x/python3", .opts = "-sE" },
        .{ .body = "#!/opt/x/python3 -I -u \r\n", .interp = "/opt/x/python3", .opts = "-I -u" },
        .{ .body = "#!/opt/x/python3\n", .interp = "/opt/x/python3", .opts = "" },
    };
    for (cases) |c| {
        var pbuf: [512]u8 = undefined;
        const p = try writeFixture(dir, "s", c.body, &pbuf);
        defer _ = posix.unlink(p.ptr);
        const sb = shebangOf(a, p) orelse return error.TestUnexpectedResult;
        try testing.expectEqualStrings(c.interp, sb.interpreter);
        try testing.expectEqualStrings(c.opts, sb.options);
    }
    var long: [400]u8 = undefined;
    @memset(&long, 'd');
    long[0] = '/';
    var pbuf: [512]u8 = undefined;
    const body = try std.fmt.allocPrint(a, "#!{s}/python3\n", .{long[0..]});
    const p = try writeFixture(dir, "long", body, &pbuf);
    defer _ = posix.unlink(p.ptr);
    try testing.expect(shebangOf(a, p) != null);
}

test "a free-threaded PythonT.framework names its PythonT interpreter (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var dbuf: [256]u8 = undefined;
    const root = try a.dupeZ(u8, fixtureDir(&dbuf, "fw-t"));
    const dirs = try bundleDirsForTest(a, root, "PythonT.framework", "3.13");
    var pbuf: [512]u8 = undefined;
    const launcher = try a.dupeZ(u8, try writeFixtureMode(dirs[3], "python3.13t", try buildMachO(a, .{}), &pbuf, 0o755));
    const lib = try a.dupeZ(u8, try writeFixture(dirs[2], "PythonT", "the framework's library", &pbuf));
    const interp = try a.dupeZ(u8, try writeFixtureMode(dirs[7], "PythonT", try buildMachO(a, .{}), &pbuf, 0o755));
    const fw = frameworkPython(a, observePath(a, launcher)) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(try realpathOf(a, interp), try realpathOf(a, fw.interpreter));
    removeForTest(&.{ launcher, interp, lib }, &dirs, root);
}

pub fn fuzzSeeds(a: std.mem.Allocator) ![]const []const u8 {
    var seeds: std.ArrayList([]const u8) = .empty;
    try seeds.append(a, try buildElf(a, .{}));
    try seeds.append(a, try buildElf(a, .{ .class64 = false, .endian = .big }));
    try seeds.append(a, try buildElf(a, .{ .interp = false }));
    const lv = try buildMachO(a, .{ .flags = cs_require_lv });
    const plain = try buildMachO(a, .{ .flags = 0, .platform = 16, .second_cd = .{ .flags = cs_require_lv, .platform = 0 } });
    try seeds.append(a, lv);
    try seeds.append(a, plain);
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;
    try seeds.append(a, try buildFat(a, &.{ plain, lv }, &.{ other, hostCpuType() }, false));
    try seeds.append(a, try buildFat(a, &.{ plain, lv }, &.{ other, hostCpuType() }, true));
    try seeds.append(a, "#!/bin/sh\necho hi\n");
    return seeds.items;
}
