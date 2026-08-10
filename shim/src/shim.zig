//! Entry point of the injected library.
//!
//! Two things happen here and nowhere else: the constructor is registered, and the
//! platform's symbol-replacement file is pulled into the compilation.

const builtin = @import("builtin");
const common = @import("common.zig");

fn ctor() callconv(.c) void {
    common.init();
}

/// Registered in `.init_array` so it runs before the target's `main`.
///
/// Initialising on the first interposed call would be simpler, but then a target that
/// performs no file operations and a target the shim never got loaded into would both
/// produce an empty trace. The engine has to tell those apart — one is a legitimate
/// PASS candidate, the other is UNKNOWN — so the `shim_ready` marker must be written
/// unconditionally, which means running before the target does anything at all.
export const sideeye_init_array: *const fn () callconv(.c) void linksection(".init_array") = &ctor;

comptime {
    // Referencing the file is what makes its `export fn` declarations part of the
    // library. macOS uses a different mechanism (`__DATA,__interpose`) and arrives
    // after the Linux ground is proven.
    if (builtin.os.tag == .linux) {
        _ = @import("linux.zig");
    }
}
