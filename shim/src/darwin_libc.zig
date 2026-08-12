//! The real libc entry points, for macOS.
//!
//! Kept in their own file so that both the interposition table (`macos.zig`) and the
//! call wrappers (`common.zig`) can reach them without importing each other.
//!
//! Calling these from inside the shim reaches the genuine functions: dyld does not
//! interpose calls that stay within one image. That is what makes it possible to avoid
//! a pointer table here — and avoiding it is not an optimisation, it is required.
//! Interposition is live from the moment this library is loaded, while a constructor
//! runs much later; anything reached through a table filled by that constructor is null
//! for every call the system libraries make in between. That gap is what made the first
//! macOS attempt return -1 to `libxpc` before `main` was ever entered.
//!
//! `@extern` rather than `extern fn` so the Zig-side name can differ from the symbol
//! name — this file needs to talk about `open` while the shim is busy exporting one.

const F = fn ([*:0]const u8, c_int, ...) callconv(.c) c_int;

pub const open = @extern(*const F, .{ .name = "open" });
pub const openat = @extern(*const fn (c_int, [*:0]const u8, c_int, ...) callconv(.c) c_int, .{ .name = "openat" });
pub const creat = @extern(*const fn ([*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "creat" });
pub const write = @extern(*const fn (c_int, [*]const u8, usize) callconv(.c) isize, .{ .name = "write" });
pub const pwrite = @extern(*const fn (c_int, [*]const u8, usize, i64) callconv(.c) isize, .{ .name = "pwrite" });
pub const writev = @extern(*const fn (c_int, *const anyopaque, c_int) callconv(.c) isize, .{ .name = "writev" });
pub const rename = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "rename" });
pub const renameat = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int, .{ .name = "renameat" });
pub const unlink = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "unlink" });
pub const unlinkat = @extern(*const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "unlinkat" });
// Never called — the remove wrapper reimplements the two-step itself — but the
// interpose table needs the original symbol's address as its key.
pub const remove = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "remove" });
pub const link = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "link" });
pub const linkat = @extern(*const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "linkat" });
pub const fsync = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "fsync" });
pub const close = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "close" });
pub const ftruncate = @extern(*const fn (c_int, i64) callconv(.c) c_int, .{ .name = "ftruncate" });
pub const truncate = @extern(*const fn ([*:0]const u8, i64) callconv(.c) c_int, .{ .name = "truncate" });
pub const mkdir = @extern(*const fn ([*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "mkdir" });
pub const mkdirat = @extern(*const fn (c_int, [*:0]const u8, c_uint) callconv(.c) c_int, .{ .name = "mkdirat" });
pub const rmdir = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "rmdir" });
pub const fork = @extern(*const fn () callconv(.c) c_int, .{ .name = "fork" });
pub const vfork = @extern(*const fn () callconv(.c) c_int, .{ .name = "vfork" });
pub const execve = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execve" });
pub const execv = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execv" });
pub const execvp = @extern(*const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "execvp" });
pub const posix_spawn = @extern(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "posix_spawn" });
pub const posix_spawnp = @extern(*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int, .{ .name = "posix_spawnp" });
pub const pthread_create = @extern(*const fn (*anyopaque, ?*const anyopaque, *const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "pthread_create" });
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
