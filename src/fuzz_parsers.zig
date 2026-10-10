//! The parsers src/fuzz.zig drives, gathered as a module of their own (#695, ADR 0112).
//!
//! Only build.zig's fuzz test binary uses this. It exists so the parsers reach that binary as
//! a separate MODULE rather than as files of its root: Zig collects a test block from every
//! file of the root module that a test reaches, so with the parsers imported as files, their
//! own four hundred-odd tests ran a second time in the fuzz binary — 36 s of its 36 s, measured
//! when this was written. Tests of another module are not collected. `posix` is here as well
//! because a file can belong to one module only, and the parsers import it.

pub const config = @import("config.zig");
pub const engine = @import("engine.zig");
pub const image = @import("image.zig");
pub const case = @import("case.zig");
pub const mcp = @import("mcp.zig");
pub const posix = @import("posix.zig");
