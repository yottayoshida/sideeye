//! Calling these from inside the shim reaches the genuine functions: dyld does not
//! interpose calls that stay within one image. That is what makes it possible to avoid
//! a pointer table here — and avoiding it is not an optimisation, it is required.
//! Interposition is live from the moment this library is loaded, while a constructor
//! runs much later; anything reached through a table filled by that constructor is null
//! for every call the system libraries make in between. That gap is what made the first
//! macOS attempt return -1 to `libxpc` before `main` was ever entered.

const F = fn ([*:0]const u8, c_int, ...) callconv(.c) c_int;

pub const open = @extern(*const F, .{ .name = "open" });
pub const openat = @extern(*const fn (c_int, [*:0]const u8, c_int, ...) callconv(.c) c_int, .{ .name = "openat" });
pub const creat = @extern(*const fn ([*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "creat" });
pub const write = @extern(*const fn (c_int, [*]const u8, usize) callconv(.c) isize, .{ .name = "write" });
pub const pwrite = @extern(*const fn (c_int, [*]const u8, usize, i64) callconv(.c) isize, .{ .name = "pwrite" });
pub const writev = @extern(*const fn (c_int, *const anyopaque, c_int) callconv(.c) isize, .{ .name = "writev" });
pub const pwritev = @extern(*const fn (c_int, *const anyopaque, c_int, i64) callconv(.c) isize, .{ .name = "pwritev" });
pub const fdatasync = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "fdatasync" });
/// The clone family (v12, #333). All three are separate stubs at separate addresses in
/// libsystem_kernel — interposing one covers none of the others — and their argument
/// orders disagree: `clonefile`'s destination is argument 1, `clonefileat`'s is 3, and
/// `fclonefileat`'s is 2 with a *source file descriptor* (not a dirfd) in argument 0.
pub const clonefile = @extern(*const fn ([*:0]const u8, [*:0]const u8, u32) callconv(.c) c_int, .{ .name = "clonefile" });
pub const clonefileat = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, u32) callconv(.c) c_int, .{ .name = "clonefileat" });
pub const fclonefileat = @extern(*const fn (c_int, c_int, [*:0]const u8, u32) callconv(.c) c_int, .{ .name = "fclonefileat" });
pub const renamex_np = @extern(*const fn ([*:0]const u8, [*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "renamex_np" });
pub const renameatx_np = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "renameatx_np" });
pub const exchangedata = @extern(*const fn ([*:0]const u8, [*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "exchangedata" });
pub const mmap = @extern(*const fn (?*anyopaque, usize, c_int, c_int, c_int, i64) callconv(.c) ?*anyopaque, .{ .name = "mmap" });
pub const mprotect = @extern(*const fn (?*anyopaque, usize, c_int) callconv(.c) c_int, .{ .name = "mprotect" });
/// The `options` word is declared `unsigned int` in one SDK header and `unsigned long`
/// in another — declared wide here, matching the wider header, since arm64 passes both
/// in a register and the wrapper only forwards it.
pub const setattrlist = @extern(*const fn ([*:0]const u8, *anyopaque, ?*anyopaque, usize, c_ulong) callconv(.c) c_int, .{ .name = "setattrlist" });
pub const fsetattrlist = @extern(*const fn (c_int, *anyopaque, ?*anyopaque, usize, c_ulong) callconv(.c) c_int, .{ .name = "fsetattrlist" });
pub const setattrlistat = @extern(*const fn (c_int, [*:0]const u8, *anyopaque, ?*anyopaque, usize, u32) callconv(.c) c_int, .{ .name = "setattrlistat" });
pub const open_dprotected_np = @extern(*const fn ([*:0]const u8, c_int, c_int, c_int, ...) callconv(.c) c_int, .{ .name = "open_dprotected_np" });
pub const rename = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "rename" });
pub const renameat = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int, .{ .name = "renameat" });
pub const unlink = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "unlink" });
pub const unlinkat = @extern(*const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "unlinkat" });
pub const remove = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "remove" });
pub const link = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "link" });
pub const linkat = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "linkat" });
pub const symlink = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "symlink" });
pub const symlinkat = @extern(*const fn ([*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int, .{ .name = "symlinkat" });
pub const fsync = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "fsync" });
pub const close = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "close" });
pub const ftruncate = @extern(*const fn (c_int, i64) callconv(.c) c_int, .{ .name = "ftruncate" });
pub const truncate = @extern(*const fn ([*:0]const u8, i64) callconv(.c) c_int, .{ .name = "truncate" });
pub const mkdir = @extern(*const fn ([*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "mkdir" });
pub const mkdirat = @extern(*const fn (c_int, [*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "mkdirat" });
pub const rmdir = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "rmdir" });
pub const mkstemp = @extern(*const fn ([*:0]u8) callconv(.c) c_int, .{ .name = "mkstemp" });
pub const mkostemp = @extern(*const fn ([*:0]u8, c_int) callconv(.c) c_int, .{ .name = "mkostemp" });
pub const mkstemps = @extern(*const fn ([*:0]u8, c_int) callconv(.c) c_int, .{ .name = "mkstemps" });
pub const mkostemps = @extern(*const fn ([*:0]u8, c_int, c_int) callconv(.c) c_int, .{ .name = "mkostemps" });
pub const mkdtemp = @extern(*const fn ([*:0]u8) callconv(.c) ?[*:0]u8, .{ .name = "mkdtemp" });
pub const fork = @extern(*const fn () callconv(.c) c_int, .{ .name = "fork" });
pub const vfork = @extern(*const fn () callconv(.c) c_int, .{ .name = "vfork" });
pub const execve = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execve" });
pub const execv = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execv" });
pub const execvp = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execvp" });
pub const posix_spawn = @extern(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "posix_spawn" });
pub const posix_spawnp = @extern(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "posix_spawnp" });
pub const pthread_create = @extern(*const fn (*anyopaque, ?*const anyopaque, *const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "pthread_create" });
pub const pthread_join = @extern(*const fn (usize, ?*?*anyopaque) callconv(.c) c_int, .{ .name = "pthread_join" });
pub const pthread_detach = @extern(*const fn (usize) callconv(.c) c_int, .{ .name = "pthread_detach" });
pub const pthread_threadid_np = @extern(*const fn (?*anyopaque, *u64) callconv(.c) c_int, .{ .name = "pthread_threadid_np" });
pub const setsid = @extern(*const fn () callconv(.c) c_int, .{ .name = "setsid" });
pub const setpgid = @extern(*const fn (c_int, c_int) callconv(.c) c_int, .{ .name = "setpgid" });
pub const fopen = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
pub const freopen = @extern(*const fn (?[*:0]const u8, [*:0]const u8, *anyopaque) callconv(.c) ?*anyopaque, .{ .name = "freopen" });
pub const fflush = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fflush" });
pub const fclose = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
pub const fseek = @extern(*const fn (*anyopaque, c_long, c_int) callconv(.c) c_int, .{ .name = "fseek" });
pub const fseeko = @extern(*const fn (*anyopaque, i64, c_int) callconv(.c) c_int, .{ .name = "fseeko" });
pub const rewind = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "rewind" });
pub const fsetpos = @extern(*const fn (*anyopaque, *const anyopaque) callconv(.c) c_int, .{ .name = "fsetpos" });

// These signatures are TRANSCRIBED, which is the thing this project otherwise refuses
// to do. There is no alternative: `sys/guarded.h` is not in the SDK (nor is
// `guardid_t`), and a symbol carries no type, so `dyld_info` and `nm` can confirm the
// name exists and nothing more. They are taken from XNU's own `bsd/sys/guarded.h`, and
// the acceptance leg that calls each one is what checks the transcription — a wrong
// arity here would not fail to compile, it would read a register the caller never
// wrote, which is exactly the failure the `open` comment above describes.
//
// `guardid_t` is `__uint64_t`, passed by pointer. Only the two open variants are
// variadic, and only when O_CREAT asks for a mode.
pub const guarded_open_np = @extern(*const fn ([*:0]const u8, *const u64, c_uint, c_int, ...) callconv(.c) c_int, .{ .name = "guarded_open_np" });
pub const guarded_open_dprotected_np = @extern(*const fn ([*:0]const u8, *const u64, c_uint, c_int, c_int, c_int, ...) callconv(.c) c_int, .{ .name = "guarded_open_dprotected_np" });
pub const guarded_close_np = @extern(*const fn (c_int, *const u64) callconv(.c) c_int, .{ .name = "guarded_close_np" });
pub const guarded_write_np = @extern(*const fn (c_int, *const u64, [*]const u8, usize) callconv(.c) isize, .{ .name = "guarded_write_np" });
pub const guarded_pwrite_np = @extern(*const fn (c_int, *const u64, [*]const u8, usize, i64) callconv(.c) isize, .{ .name = "guarded_pwrite_np" });
pub const guarded_writev_np = @extern(*const fn (c_int, *const u64, *const anyopaque, c_int) callconv(.c) isize, .{ .name = "guarded_writev_np" });
