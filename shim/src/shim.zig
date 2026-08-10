//! Entry point of the injected library.
//!
//! Two things happen here and nowhere else: the constructor is registered, and the
//! platform's symbol-installation file is pulled into the compilation.

const builtin = @import("builtin");
const common = @import("common.zig");

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
