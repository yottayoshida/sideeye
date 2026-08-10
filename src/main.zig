const std = @import("std");
const contract = @import("contract");

pub const version = "0.1.0-dev";

pub fn main() !void {
    std.debug.print(
        \\sideeye {s} (trace contract v{d})
        \\
        \\The engine is not wired up yet; this build exists so the shared contract
        \\and the shim can be built and tested. See docs/adr/0001 for the plan.
        \\
    , .{ version, contract.contract_version });
    std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
}
