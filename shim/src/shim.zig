//! Entry point of the injected library.
//!
//! Two things happen here and nowhere else: the constructor is registered, and the
//! platform's symbol-installation file is pulled into the compilation.

const builtin = @import("builtin");
const std = @import("std");
const common = @import("common.zig");

/// Nothing of a target thread's memory is ours to spend (#555). Zig's std gives every
/// thread it starts a 256 KiB alternative signal stack held in a `threadlocal`, and in a
/// preloaded library that storage joins the static TLS block glibc carves out of EVERY
/// thread's stack — the target's own included. glibc then refuses any thread whose
/// requested stack is smaller (`EINVAL` from `pthread_create`): measured on node's SIGUSR1
/// watchdog thread, which asks for `max(4 * 8192, PTHREAD_STACK_MIN)` and failed to start
/// under a shim that did nothing but load. The shim registers no handler with
/// `SA_ONSTACK` and starts no thread through std, so it never used that stack. Without it
/// the shim's TLS is a few words (21 bytes on aarch64 ReleaseSafe, 24 on x86_64 Debug),
/// and acceptance holds it under 1 KiB.
pub const std_options: std.Options = .{ .signal_stack_size = null };

const is_macos = builtin.os.tag == .macos;

fn ctor() callconv(.c) void {
    common.init();
}

/// Runs before the target's `main`. The section name is the only difference between
/// the platforms: ELF uses `.init_array`, Mach-O uses `__DATA,__mod_init_func`.
///
/// Initialising on the first interposed call would be simpler, but then a target that
/// performs no file operations and a target the shim never got loaded into would both
/// produce an empty trace. The engine has to tell those apart — one is a legitimate
/// PASS candidate, the other is UNKNOWN — so the `shim_ready` marker must be written
/// unconditionally, which means running before the target does anything at all.
const ctor_section = if (is_macos) "__DATA,__mod_init_func" else ".init_array";

export const sideeye_init_array: *const fn () callconv(.c) void linksection(ctor_section) = &ctor;

comptime {
    // Referencing the file is what makes its symbol installation part of the library.
    if (is_macos) {
        _ = @import("macos.zig");
    } else {
        _ = @import("linux.zig");
    }
}
