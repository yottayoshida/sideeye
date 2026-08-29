//! What the operation's executable file looked like when the run started.
//!
//! This module exists because a refusal was guessing. `no_shim_marker` proves only that
//! the trace carried no `shim_ready` record, and the message that accompanied it listed
//! candidate causes — statically linked, hardened, not injected, and on macOS an
//! Apple-shipped platform binary — none of which the engine had looked at. README's
//! first sentence about the limits is "Sideeye refuses to guess"; a list of guesses in
//! the one message a refused user actually reads contradicts it.
//!
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
//!
//! Integers are read one at a time with an explicit endianness, never by casting a
//! struct over the bytes. That is `contract.zig`'s rule and it earns its keep twice
//! here: Mach-O headers are host-endian while every code-signing blob is big-endian, so
//! a single file needs both, and the two are three fields apart.

const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");

// ---------------------------------------------------------------------------
// Caps. Each one bounds a count the file itself declares, so none of them can be
// grown by the file being measured. They are deliberately far above anything a real
// executable carries — the point is to bound the loop, not to judge the binary — and
// a file that exceeds one is `undecidable`, never a partial answer.

/// A universal binary carries one entry per architecture. Apple has shipped at most
/// four in a shipping artifact; 64 leaves room without letting the count drive a loop.
const max_fat_arch = 64;
/// `ncmds` from the Mach-O header. Real binaries are in the tens.
const max_load_commands = 4096;
/// `sizeofcmds`, the byte span the load commands occupy.
const max_sizeofcmds = 1 << 20;
/// `count` from the signature SuperBlob. A signature carries a handful of blobs.
const max_superblob_entries = 256;
/// `e_phnum` from an ELF header.
const max_program_headers = 4096;

// Mach-O and code-signing constants that std.macho does not name. The values are
// Apple's (`cs_blobs.h`); the two flags below were also read off this machine with
// `codesign -dv --verbose=2` on 2026-08-29: the Command Line Tools git reports
// `flags=0x2000(library-validation)`, a locally built binary `0x20002(adhoc,
// linker-signed)`, and `/usr/bin/true` `0x0(none)` with `Platform identifier=16`.
pub const cs_require_lv: u32 = 0x2000;
pub const cs_runtime: u32 = 0x10000;
const cs_adhoc: u32 = std.macho.CS_ADHOC;
const cs_linker_signed: u32 = std.macho.CS_LINKER_SIGNED;

const cpu_type_x86_64: i32 = 0x01000007;
const cpu_type_arm64: i32 = 0x0100000C;

// ---------------------------------------------------------------------------

/// Fields read out of the code directory the OS would most plausibly use. Every
/// accessor below is named after the bit, not after what the bit is thought to prevent.
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

/// Why nothing could be read. Each value is a thing that happened, not a diagnosis.
pub const Unreadable = enum {
    no_such_file,
    permission_denied,
    not_a_regular_file,
    read_failed,
};

/// Why the file was read but no single answer follows from it. These are the cases
/// where guessing would be easy and wrong, so they are their own outcome.
pub const Undecidable = enum {
    /// More than one slice matches this machine's CPU and none matches its subtype, or
    /// several do. Which one the kernel would pick is not decided here.
    slice_not_unique,
    /// Several code directories were present and they disagree about the fields this
    /// module reads. XNU picks by hash-type preference; that ordering is not
    /// reimplemented here.
    code_directories_disagree,
    /// A declared count or span exceeded a cap above, or an offset ran past the file.
    structure_out_of_range,
};

pub const Elf = struct {
    /// A `PT_INTERP` program header is present, i.e. the file names an interpreter and
    /// is therefore dynamically linked.
    has_interp: bool,
    class64: bool,
};

pub const MachO = struct {
    /// `MH_DYLDLINK` in the Mach-O header.
    dyldlink: bool,
    /// Absent when the slice carries no `LC_CODE_SIGNATURE`.
    signing: ?Signing,
};

pub const Facts = union(enum) {
    /// `argv[0]` carried no `/`, so the OS resolved it through `PATH` and Sideeye did
    /// not. Reimplementing `execvp`'s search — empty components meaning the current
    /// directory, relative components resolving against the child's cwd, the `ENOEXEC`
    /// shell fallback, `EACCES` continuing to the next candidate — would put a second
    /// copy of that rule in the tree, and the copy that drifts is the one that names
    /// the wrong file with confidence.
    not_resolved,
    unreadable: Unreadable,
    /// Read, and neither ELF nor Mach-O. A `#!` script lands here; so does anything
    /// else. What the interpreter of a script would have been is a separate question
    /// and a separate issue.
    unrecognised,
    undecidable: Undecidable,
    elf: Elf,
    macho: MachO,
};

pub const Observation = struct {
    /// The path measured, or null when `facts` is `not_resolved`. Target-derived, so
    /// every caller that prints it must send it through `textShown` first.
    path: ?[]const u8,
    /// The file's length at the moment of the reading. Part of what `sameAnswer`
    /// compares, and never printed as a fact about the run.
    size: ?u64,
    facts: Facts,
};

/// Would a second reading have said anything different from the first?
///
/// Deliberately not "is it the same file". Comparing the answers rather than an inode
/// keeps the comparison at the altitude of the claim: the refusal reports fields, so the
/// question that matters is whether those fields moved.
pub fn sameAnswer(a: Observation, b: Observation) bool {
    if (a.size != b.size) return false;
    return std.meta.eql(a.facts, b.facts);
}

/// Measure the file `argv0` names. Call this *before* the spawn.
///
/// `cwd` is the directory the child will `chdir` into (`[define] cwd`, #395); a
/// relative `argv[0]` is resolved against it because that is what the child will do.
pub fn observe(arena: std.mem.Allocator, argv0: []const u8, cwd: ?[]const u8) Observation {
    if (std.mem.indexOfScalar(u8, argv0, '/') == null)
        return .{ .path = null, .size = null, .facts = .not_resolved };

    const path = resolveAgainst(arena, argv0, cwd) orelse
        return .{ .path = null, .size = null, .facts = .{ .unreadable = .read_failed } };
    const path_z = arena.dupeZ(u8, path) catch
        return .{ .path = path, .size = null, .facts = .{ .unreadable = .read_failed } };

    // O_NONBLOCK because the path comes from the target's own define: a FIFO there
    // would otherwise block this open until a writer appeared, i.e. forever, and the
    // engine would hang before the OS ever got to reject the exec. `posix.zig`'s flag
    // comment carries the incident (#5) this inherits.
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

/// Read the same path again, for the comparison `sameAnswer` makes. Separate from
/// `observe` only in that it takes the path already resolved: re-running the resolution
/// would fold two different changes — the file moved, the cwd moved — into one answer.
pub fn reobserve(arena: std.mem.Allocator, path: []const u8) Observation {
    const path_z = arena.dupeZ(u8, path) catch
        return .{ .path = path, .size = null, .facts = .{ .unreadable = .read_failed } };
    // O_NONBLOCK because the path comes from the target's own define: a FIFO there
    // would otherwise block this open until a writer appeared, i.e. forever, and the
    // engine would hang before the OS ever got to reject the exec. `posix.zig`'s flag
    // comment carries the incident (#5) this inherits.
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

// ---------------------------------------------------------------------------
// Parsing. Every read goes through `at`, which is the only place a file offset turns
// into bytes, so "did this offset run past the end" is answered once.

const Reader = struct {
    fd: c_int,
    size: u64,

    /// Read exactly `buf.len` bytes at `off`, or fail. A short read is a failure, not a
    /// shorter answer: every field below is fixed-width and a partial one is noise.
    /// Positional, so two field reads never depend on each other's cursor.
    fn at(r: Reader, off: u64, buf: []u8) bool {
        if (buf.len == 0) return true;
        // Overflow is checked; running past the end is not, on purpose. A short read
        // already fails below, and a `size` bound taken from one `lseek` cannot be
        // reddened by any test — a regular file never returns `buf.len` bytes from past
        // its end — so it would be a guard nothing can falsify.
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

// --- ELF -------------------------------------------------------------------

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

    // Offsets from the ELF spec. They differ between the two classes, which is exactly
    // the sort of thing a struct cast would get right on one and silently wrong on the
    // other.
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

// --- Mach-O ----------------------------------------------------------------

fn hostCpuType() i32 {
    return switch (builtin.cpu.arch) {
        .aarch64 => cpu_type_arm64,
        .x86_64 => cpu_type_x86_64,
        else => 0,
    };
}

/// Pick the slice this machine would run, without guessing.
///
/// Selection is by CPU *type* only, and the subtype is not consulted at all.
///
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
    // The header is host-endian for a native slice; both spellings are accepted so a
    // cross-endian file is read rather than mistaken for something else.
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
        // A zero or unaligned size would loop forever or walk off the ladder.
        if (cmdsize < 8 or cmdsize % 4 != 0) return .{ .undecidable = .structure_out_of_range };

        // The command must lie wholly inside the span the header declared. Without this
        // a command that straddles the end is read anyway, and its fields come from
        // whatever follows the load-command region.
        const cmd_end = std.math.add(u64, off, cmdsize) catch
            return .{ .undecidable = .structure_out_of_range };
        if (cmd_end > limit) return .{ .undecidable = .structure_out_of_range };

        if (cmd == @intFromEnum(std.macho.LC.CODE_SIGNATURE)) {
            // Noted, not read. Acting on the first signature the moment it appears would
            // leave the rest of the declared commands unwalked, and the check below —
            // that the span actually held every command the header counted — would never
            // run on the one path where a signature exists. That was the shape review
            // found: `ncmds` of two with room for one, answered from the one.
            if (cmdsize < 16) return .{ .undecidable = .structure_out_of_range };
            if (sig_cmd == null) sig_cmd = off;
        }
        off = cmd_end;
    }
    // The header must agree with itself before anything read from it is reported. Ending
    // the span with commands still declared means it does not, and "carries no code
    // signature" — or a signature read from the part that did fit — would be a claim the
    // file never supported.
    if (i < ncmds) return .{ .undecidable = .structure_out_of_range };

    const cmd_off = sig_cmd orelse return .{ .macho = .{ .dyldlink = dyldlink, .signing = null } };
    // `datasize` bounds the signature. Reading it is what makes "its code directory
    // carries X" a statement about the signature rather than about bytes that happen to
    // sit at the right offset: a `datasize` of zero, or one too small to hold what the
    // blobs claim, must refuse rather than reach past.
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

/// Read the code directory's `flags` and `platform`.
///
/// A signature may carry more than one code directory (a primary plus alternates for
/// other hash types). XNU chooses among them by hash-type preference; that ordering is
/// not reimplemented here. Instead every code directory in the index is read, and if
/// they agree on both fields the agreed value is the answer — which is the common case,
/// alternates being the same statement hashed differently. If they disagree, so is the
/// answer: `code_directories_disagree`.
///
/// Everything in a signature blob is big-endian regardless of the host, which is why
/// `.big` appears on every read below while the load commands above used the header's.
fn readSigning(r: Reader, at: u64, hi: u64) SigResult {
    // Every offset below is checked against `hi`, the end of the region the load command
    // declared. Without that the reads still land inside the file and still return
    // plausible integers, and the sentence built from them — "its code directory carries
    // the library-validation flag" — becomes a statement about bytes that were never
    // part of a signature.
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

    // The SuperBlob's own declared length narrows the region further; a blob may not
    // reach past what the superblob says it holds.
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

        // The blob's own declared length has to cover the fields read from it. A code
        // directory claiming eight bytes does not carry a platform byte at offset 38,
        // and taking one from there would be reading the next blob.
        const blob_len = r.u32At(blob_at + 4, .big) orelse
            return .{ .undecidable = .structure_out_of_range };
        const blob_end = std.math.add(u64, blob_at, blob_len) catch
            return .{ .undecidable = .structure_out_of_range };
        if (blob_end > super_end) return .{ .undecidable = .structure_out_of_range };
        // Field offsets inside CodeDirectory: flags at 12, platform at 38. `platform`
        // is a byte three fields past the end of the u32 block, and it is the field that
        // carries `/usr/bin/true`'s identity while its `flags` are zero — reading only
        // `flags` is how a platform binary gets missed.
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

// ---------------------------------------------------------------------------
// Tests. The parser's own falsification is byte fixtures, one field at a time: a host
// binary is a single sample whose value can change under a system update, and
// `/usr/bin/git` (the Xcode selector shim, platform 16) and the Command Line Tools git
// (library validation) are different files with opposite expectations, so a corpus
// keyed by path is one rename away from asserting the wrong thing. The host smoke test
// lives beside these and is skipped off macOS.

const testing = std.testing;

/// A minimal 64-bit little-endian Mach-O with one LC_CODE_SIGNATURE and one code
/// directory. Every test below starts from this and breaks exactly one field, so a
/// failure names the field rather than "the parser".
fn buildMachO(a: std.mem.Allocator, opts: struct {
    flags: u32 = 0,
    platform: u8 = 0,
    mh_flags: u32 = std.macho.MH_DYLDLINK,
    cd_magic: u32 = std.macho.CSMAGIC_CODEDIRECTORY,
    super_magic: u32 = std.macho.CSMAGIC_EMBEDDED_SIGNATURE,
    second_cd: ?struct { flags: u32, platform: u8 } = null,
    ncmds_override: ?u32 = null,
    /// Overrides for the declared lengths the parser is required to honour. Each one
    /// exists so a test can drive exactly the field whose check it names, rather than
    /// asserting a refusal that some other bound happens to produce first.
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
    const path = std.fmt.bufPrintZ(out, "{s}/{s}", .{ dir, name }) catch unreachable;
    const fd = posix.open(path.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return error.SkipZigTest;
    defer _ = posix.close(fd);
    if (bytes.len != 0) {
        const n = posix.write(fd, bytes.ptr, bytes.len);
        if (n < 0 or @as(usize, @intCast(n)) != bytes.len) return error.SkipZigTest;
    }
    return path;
}

/// Classify a byte string by putting it on disk and reading it back through the same
/// path production takes — `observe`, not a hand-built Reader. A harness that skips the
/// production entry point measures its own copy of the logic.
/// A universal binary wrapping `slices`, each declared with the CPU type at the same
/// index. `is64` selects the FAT64 layout, whose entries are 32 bytes with 64-bit
/// offsets rather than 20 with 32-bit ones — the difference a single-layout reader gets
/// silently wrong, because a FAT64 offset read as a u32 lands on the high half of zero.
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
    return observe(arena.allocator(), path, null).facts;
}

test "the platform byte is read even when flags are zero" {
    // The shape of `/usr/bin/true`: nothing in `flags`, identity in `platform`. A
    // parser that reads only `flags` returns the same answer here as for an unsigned
    // binary, which is the miss this test exists to catch.
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
    // The bits are read (they are in `flags`), and none of the three predicates the
    // refusal actually branches on fires for them. Asserted through those predicates
    // rather than through accessors of their own: an accessor no production path reads
    // is kept alive by its test and by nothing else.
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
    // The first version of this test lopped eight bytes off the end and expected a
    // refusal. It failed, correctly: `flags` sits at +12 and `platform` at +38 inside
    // the code directory, so a tail cut removes nothing either read touches. A
    // truncation test has to cut where the parser actually looks, or it passes for a
    // reason unrelated to the bounds check it claims to hold.
    const full = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .platform = 16 });
    defer testing.allocator.free(full);

    // Laid out the way buildMachO does: mach header, one load command, the superblob
    // head and its single index entry.
    const cd_at: usize = 32 + 16 + 12 + 8;

    // One byte short of `platform`, with `flags` fully present. An unchecked read here
    // returns a zero platform, and a zero platform is the same value an ordinary signed
    // binary carries — the failure would be silent and plausible.
    const cut_platform = try factsOfBytes("cut-platform", full[0 .. cd_at + 38]);
    try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, cut_platform);

    // Short of `flags` as well.
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
    // arm64 and arm64e share a CPU type. Which one the kernel grades as runnable is not
    // restated here, so two candidates is an admission rather than a pick.
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
    // Without these the reads still land inside the file and still return plausible
    // integers — which is the failure mode, because the sentence built from them says
    // the values came out of a code directory.
    // `datasize` of zero: the signature region is empty, so nothing in it can be read.
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
    // The SuperBlob claiming more than the load command allotted it.
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .super_len_override = 1 << 20 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-super", b));
    }
    // A code directory that declares eight bytes does not reach its own platform byte at
    // offset 38; reading one from there would be reading whatever follows the blob.
    {
        const b = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .cd_len_override = 8 });
        defer testing.allocator.free(b);
        try testing.expectEqual(Facts{ .undecidable = .structure_out_of_range }, try factsOfBytes("len-cd", b));
    }
    // A load command that runs past the span the header declared.
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
    // `ncmds` of two with room for one. The command that fits is a valid, readable
    // signature, so a walk that acts on the first one it finds answers happily and never
    // reaches the count check — which is the path review found still open after the
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
    // The file being parsed is named by the target's own define, so every field is
    // attacker-shaped: counts, offsets and lengths that may point anywhere. This walks
    // mutations of real fixtures — every truncation, then every structural byte driven
    // to the two values that break loops and offsets — and asserts only that a value
    // comes back.
    //
    // It exists because of how two mutation runs failed. Killing `FAT64 offsets` and
    // `fat entry size` aborted with SIGABRT rather than a clean assertion, and the abort
    // was in the *test* unwrapping a null, not in the parser. That is a test asserting a
    // shape with nothing asserting the parser stays on its feet at all.
    const thin = try buildMachO(testing.allocator, .{ .flags = cs_require_lv, .platform = 16 });
    defer testing.allocator.free(thin);
    const other: i32 = if (hostCpuType() == cpu_type_arm64) cpu_type_x86_64 else cpu_type_arm64;

    // Both fat layouts are walked, not just the thin one. The first version of this test
    // covered thin Mach-O and ELF only — leaving the two code paths whose mutations had
    // aborted, fat and FAT64, untouched by the very walk written because of them.
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
            _ = observe(arena.allocator(), path, null);
            _ = posix.unlink(path.ptr);
        }
        for ([_]u8{ 0xff, 0x00 }) |fill| {
            var i: usize = 0;
            while (i < fixture.len) : (i += 1) {
                @memcpy(scratch[0..fixture.len], fixture);
                scratch[i] = fill;
                const path = try writeFixture(dir, "h", scratch[0..fixture.len], &pbuf);
                _ = observe(arena.allocator(), path, null);
                _ = posix.unlink(path.ptr);
            }
        }
    }
    // Reaching here is the assertion: no panic, no hang, no unbounded read.
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
    const obs = observe(arena.allocator(), "git", null);
    try testing.expectEqual(Facts.not_resolved, obs.facts);
    try testing.expect(obs.path == null);
    try testing.expect(obs.size == null);
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
    const with = observe(arena.allocator(), "./prog", dir);
    try testing.expect(with.facts == .macho);
    const without = observe(arena.allocator(), "./prog", "/nonexistent-cwd-for-this-test");
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

    const before = observe(a, path, null);
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

    // /usr/bin/true: flags 0, platform 16, and universal with an arm64e slice on Apple
    // silicon — the file that fails a subtype-exact slice picker.
    const t = observe(a, "/usr/bin/true", null);
    if (t.facts == .macho) {
        const s = t.facts.macho.signing.?;
        try testing.expect(s.platformNamed());
        try testing.expect(!s.libraryValidation());
    }

    // A second host file, read only to show the reader reaches a Mach-O at all. No
    // expectation is pinned on its flags: what a system binary carries is Apple's to
    // change, and the parser's own falsification is the fixtures above.
    const other = observe(a, "/bin/ls", null);
    try testing.expect(other.facts == .macho or other.facts == .undecidable);
}
