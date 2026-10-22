const builtin = @import("builtin");
const std = @import("std");
const common = @import("common.zig");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const is_macos = builtin.os.tag == .macos;

fn ctor() callconv(.c) void {
    common.init();
}

/// Initialising on the first interposed call would be simpler, but then a target that
/// performs no file operations and a target the shim never got loaded into would both
/// produce an empty trace. The engine has to tell those apart — one is a legitimate
/// PASS candidate, the other is UNKNOWN — so the `shim_ready` marker must be written
/// unconditionally, which means running before the target does anything at all.
const ctor_section = if (is_macos) "__DATA,__mod_init_func" else ".init_array";

export const sideeye_init_array: *const fn () callconv(.c) void linksection(ctor_section) = &ctor;

comptime {
    if (is_macos) {
        _ = @import("macos.zig");
    } else {
        _ = @import("linux.zig");
    }
}
