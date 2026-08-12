//! `sideeye mcp` — a stateless MCP 2026-07-28 stdio server (ADR 0010).
//!
//! The server owns fd 1: a self-exec'd `explore`/`replay` — which prints a full report
//! to *its* stdout — cannot leak a byte onto the MCP transport. Every child's stdout
//! goes to a work-dir file via `runChildCaptureMinimalEnv`, and only one-line JSON-RPC
//! responses are written to fd 1 here.
//!
//! Deliberately thin (ADR 0001 / #40): the server holds no state and no judgement. A
//! tool call becomes `<self> explore --config <path> --json <temp>` (or `replay`); the
//! verdict is read back from the `--json` file as the tool payload. The one in-process
//! shortcut considered (calling the engine directly) is rejected because every verdict
//! path in main.zig ends in `std.process.exit` — there is nothing to return.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const posix = @import("posix.zig");

const protocol_version = "2026-07-28";

/// The canonical path of the running binary — never argv[0], which may be a PATH name,
/// a relative path, or a wrapper (R1 Critical: execvp PATH hijack). Linux reads
/// `/proc/self/exe`; macOS reads `_NSGetExecutablePath` then realpaths it. Returns null
/// if it cannot be resolved — the adapter then refuses to start rather than self-exec a
/// binary it cannot name.
fn canonicalSelf() ?[]const u8 {
    if (builtin.os.tag == .linux) {
        const n = posix.readlink("/proc/self/exe", &self_buf, self_buf.len - 1);
        if (n <= 0 or n >= self_buf.len - 1) return null;
        self_buf[@intCast(n)] = 0;
        return self_buf[0..@intCast(n)];
    }
    // macOS: _NSGetExecutablePath may return a symlink/relative path; canonicalize it.
    var raw: [contract.max_path]u8 = undefined;
    var size: u32 = raw.len;
    if (posix._NSGetExecutablePath(&raw, &size) != 0) return null;
    if (posix.realpath(@ptrCast(&raw), &self_buf)) |p| return std.mem.span(p);
    return null;
}
var self_buf: [contract.max_path]u8 = undefined;

/// One line to fd 1, the MCP transport. Nothing else may write here.
fn emit(s: []const u8) void {
    var off: usize = 0;
    while (off < s.len) {
        const w = posix.write(1, s[off..].ptr, s.len - off);
        if (w <= 0) transportDead();
        off += @intCast(w);
    }
    if (posix.write(1, "\n", 1) <= 0) transportDead();
}

/// A failed transport write cannot be skipped over: returning mid-message leaves a
/// partial line on fd 1, and every response after it would be glued to the fragment —
/// framing corruption the client cannot recover from. Dying is the honest move.
fn transportDead() noreturn {
    const msg = "sideeye mcp: cannot write to the transport (fd 1); exiting\n";
    _ = posix.write(2, msg.ptr, msg.len);
    std.process.exit(1);
}

pub fn runServer(gpa: std.mem.Allocator) void {
    const self = canonicalSelf() orelse {
        const msg = "sideeye mcp: could not resolve the canonical path of this binary; refusing to start\n";
        _ = posix.write(2, msg.ptr, msg.len);
        std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
    };
    // The workspace root that config/case paths must resolve inside (R1 Critical: a
    // tool-supplied path must not reach outside a known root). Required.
    const root = if (posix.getenv("SIDEEYE_MCP_ROOT")) |r| resolveDir(std.mem.span(r)) else null;
    if (root == null) {
        const msg = "sideeye mcp: SIDEEYE_MCP_ROOT is not set or unresolvable; refusing to start\n";
        _ = posix.write(2, msg.ptr, msg.len);
        std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
    }
    server_root = root.?;
    var buf: [256 * 1024]u8 = undefined;
    var filled: usize = 0;
    // While draining, the current line overflowed the buffer; everything up to and
    // including the next newline is discarded, so the tail of an oversized line is never
    // mis-parsed as a fresh message.
    var draining = false;
    while (true) {
        // A message is one line. Scan what we have for a newline before reading more.
        if (std.mem.indexOfScalar(u8, buf[0..filled], '\n')) |nl| {
            if (!draining) handle(gpa, self, buf[0..nl]);
            draining = false;
            const rest = filled - (nl + 1);
            std.mem.copyForwards(u8, buf[0..rest], buf[nl + 1 .. filled]);
            filled = rest;
            continue;
        }
        if (filled == buf.len) {
            // A line longer than the buffer: discard it, and keep discarding until the
            // next newline (draining) so its tail is not read as a new message.
            draining = true;
            filled = 0;
            continue;
        }
        const n = posix.read(0, buf[filled..].ptr, buf.len - filled);
        if (n <= 0) {
            // EOF. A final message not terminated by a newline (common — many writers
            // don't add a trailing \n) still has to be processed — unless we were
            // draining an oversized line, in which case there is no whole message.
            if (filled > 0 and !draining) handle(gpa, self, buf[0..filled]);
            return;
        }
        filled += @intCast(n);
    }
}

fn handle(gpa: std.mem.Allocator, self: []const u8, line: []const u8) void {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, trimmed, .{}) catch {
        emit("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}");
        return;
    };
    if (parsed != .object) {
        emit("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}");
        return;
    }
    const obj = parsed.object;
    const id = obj.get("id"); // ?Value; absent => notification
    // JSON-RPC 2.0 requires the version tag on every message; a missing or wrong tag
    // is an Invalid Request, not something to guess past.
    const jsonrpc_ok = switch (obj.get("jsonrpc") orelse std.json.Value{ .null = {} }) {
        .string => |v| std.mem.eql(u8, v, "2.0"),
        else => false,
    };
    if (!jsonrpc_ok) {
        if (id != null) emitError(arena, id.?, -32600, "Invalid Request: not JSON-RPC 2.0");
        return;
    }
    const method = switch (obj.get("method") orelse std.json.Value{ .null = {} }) {
        .string => |m| m,
        else => {
            if (id != null) emitError(arena, id.?, -32600, "Invalid Request: missing method");
            return;
        },
    };

    if (id == null) return; // notification: no response (e.g. notifications/cancelled)

    // Every request carries its protocol version and capabilities in `params._meta`
    // (the stateless model — no handshake establishes them once). Checked on ALL
    // methods, or discover/list would succeed unvalidated. `_meta` lives under
    // `params`, not at the top level (schema.ts: RequestParams._meta).
    const params: ?std.json.ObjectMap = switch (obj.get("params") orelse std.json.Value{ .null = {} }) {
        .object => |p| p,
        else => null,
    };
    switch (checkMeta(params)) {
        .ok => {},
        .missing => |what| return emitError(arena, id.?, -32602, what),
        .unsupported => |v| return emitUnsupportedVersion(arena, id.?, v),
    }

    if (std.mem.eql(u8, method, "server/discover")) {
        // DiscoverResult: supportedVersions[] + capabilities — and, because it extends
        // CacheableResult (schema.ts), ttlMs and cacheScope are REQUIRED, as is
        // resultType on every result a 2026-07-28 server emits. The first version
        // omitted all three; a schema-validating client would have rejected discover
        // before anything else could work. The catalogue is static for the server's
        // lifetime: a 1h TTL, private (stdio is a single-user pipe).
        emitResult(arena, id.?, "\"resultType\":\"complete\",\"ttlMs\":3600000,\"cacheScope\":\"private\"," ++
            "\"supportedVersions\":[\"2026-07-28\"],\"capabilities\":{\"tools\":{\"listChanged\":false}}");
    } else if (std.mem.eql(u8, method, "tools/list")) {
        emitResult(arena, id.?, toolsListBody());
    } else if (std.mem.eql(u8, method, "tools/call")) {
        callTool(gpa, arena, self, id.?, obj);
    } else {
        emitError(arena, id.?, -32601, "Method not found");
    }
}

const MetaCheck = union(enum) { ok, missing: []const u8, unsupported: []const u8 };

/// Validate the required per-request `_meta` fields (schema.ts, 2026-07-28): under
/// `params._meta`, the protocol version (must be the one we speak) and the client
/// capabilities (presence only). clientInfo is optional and not required here.
fn checkMeta(params: ?std.json.ObjectMap) MetaCheck {
    const p = params orelse return .{ .missing = "missing params (with _meta)" };
    const meta = switch (p.get("_meta") orelse std.json.Value{ .null = {} }) {
        .object => |m| m,
        else => return .{ .missing = "missing params._meta" },
    };
    const ver = switch (meta.get("io.modelcontextprotocol/protocolVersion") orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => return .{ .missing = "missing _meta protocolVersion" },
    };
    switch (meta.get("io.modelcontextprotocol/clientCapabilities") orelse std.json.Value{ .null = {} }) {
        .object => {},
        else => return .{ .missing = "missing _meta clientCapabilities (must be an object)" },
    }
    if (!std.mem.eql(u8, ver, protocol_version)) return .{ .unsupported = ver };
    return .ok;
}

/// The tool catalogue: two tools, both taking a single path (no raw command — R1
/// Critical). Deterministic order (spec: caching / prompt-cache friendliness).
/// ListToolsResult also extends CacheableResult, so ttlMs + cacheScope are required.
fn toolsListBody() []const u8 {
    return "\"resultType\":\"complete\",\"ttlMs\":3600000,\"cacheScope\":\"private\",\"tools\":[" ++
        "{\"name\":\"sideeye_explore_config\"," ++
        "\"description\":\"Explore crash-consistency for a target defined by a sideeye.toml (its path must be inside SIDEEYE_MCP_ROOT). Returns the verdict report. NOTE: the operation in the config is executed; the config is a trust boundary.\"," ++
        "\"inputSchema\":{\"type\":\"object\",\"properties\":{\"config_path\":{\"type\":\"string\",\"description\":\"Path to a sideeye.toml inside the server root\"}},\"required\":[\"config_path\"],\"additionalProperties\":false}}," ++
        "{\"name\":\"sideeye_replay_case\"," ++
        "\"description\":\"Replay a saved counterexample case (its path must be inside SIDEEYE_MCP_ROOT). Returns the verdict, or 'case no longer applies' if the recording changed.\"," ++
        "\"inputSchema\":{\"type\":\"object\",\"properties\":{\"case_path\":{\"type\":\"string\",\"description\":\"Path to a saved case JSON inside the server root\"}},\"required\":[\"case_path\"],\"additionalProperties\":false}}" ++
        "]";
}

fn callTool(gpa: std.mem.Allocator, arena: std.mem.Allocator, self: []const u8, id: std.json.Value, obj: std.json.ObjectMap) void {
    const params = switch (obj.get("params") orelse std.json.Value{ .null = {} }) {
        .object => |p| p,
        else => return emitError(arena, id, -32602, "Invalid params"),
    };
    const name = switch (params.get("name") orelse std.json.Value{ .null = {} }) {
        .string => |n| n,
        else => return emitError(arena, id, -32602, "Invalid params: name"),
    };
    const args = switch (params.get("arguments") orelse std.json.Value{ .null = {} }) {
        .object => |a| a,
        else => return emitError(arena, id, -32602, "Invalid params: arguments"),
    };

    if (std.mem.eql(u8, name, "sideeye_explore_config")) {
        const p = strArg(args, "config_path") orelse return emitError(arena, id, -32602, "Invalid params: config_path");
        runExplore(gpa, arena, self, id, .explore, p);
    } else if (std.mem.eql(u8, name, "sideeye_replay_case")) {
        const p = strArg(args, "case_path") orelse return emitError(arena, id, -32602, "Invalid params: case_path");
        runExplore(gpa, arena, self, id, .replay, p);
    } else {
        emitError(arena, id, -32602, "Unknown tool");
    }
}

const RunKind = enum { explore, replay };

fn runExplore(gpa: std.mem.Allocator, arena: std.mem.Allocator, self: []const u8, id: std.json.Value, kind: RunKind, path_in: []const u8) void {
    // The tool-supplied path must resolve inside the server root. Refuse traversal
    // (../../etc/x), symlinks out, and absolute escapes — realpath then prefix-check
    // on a component boundary (R1 Critical).
    const path = resolveInsideRoot(arena, path_in) orelse
        return emitToolError(arena, id, "the path is outside the server root (SIDEEYE_MCP_ROOT), or does not exist");

    const shim = if (posix.getenv("SIDEEYE_MCP_SHIM")) |s| std.mem.span(s) else
        return emitToolError(arena, id, "SIDEEYE_MCP_SHIM is not set; the server needs a shim path");
    const work = if (posix.getenv("SIDEEYE_MCP_WORK")) |w| std.mem.span(w) else "/tmp/sideeye-mcp";
    var wbuf: [contract.max_path]u8 = undefined;
    const wz = std.fmt.bufPrintZ(&wbuf, "{s}", .{work}) catch return emitToolError(arena, id, "work path too long");
    // 0700: reports and captures under here hold target output the caller sent; they
    // are not world-readable. mkdir failure other than "already exists" is fatal.
    if (posix.mkdir(wz.ptr, 0o700) != 0 and std.c._errno().* != 17)
        return emitToolError(arena, id, "the work directory could not be created");

    counter += 1;
    const temp_json = std.fmt.allocPrint(arena, "{s}/report-{d}.json", .{ work, counter }) catch return emitToolError(arena, id, "oom");
    const child_out = std.fmt.allocPrint(arena, "{s}/child-{d}.out", .{ work, counter }) catch return emitToolError(arena, id, "oom");

    // A previous server process may have left report-N / child-N behind — the counter
    // is per-process, so two servers sharing a work dir collide on the same names. The
    // capture opens O_EXCL, the collision aborts the child at 126, and the parent then
    // reads the PREVIOUS run's report-N.json back as THIS call's verdict (measured
    // 2026-08-12: a second server answered with the first server's report, about a
    // different target). Unlink both names first: whatever exists at them afterwards
    // was written by this call's child or by nobody. The work dir is user-owned by
    // contract (ADR 0010), so these are our own leftovers, not someone else's files.
    unlinkPath(temp_json);
    unlinkPath(child_out);

    // The vetted absolute path (realpath'd, confirmed inside the root) is handed to the
    // child as-is. A copy-into-work-dir would close the check→open TOCTOU window, but it
    // breaks a config's own relative resolution (state = "./state" is relative to the
    // config's directory, ADR 0007), so it is the wrong fix here. The residual TOCTOU
    // requires the root to be attacker-writable between the check and the child's open;
    // SIDEEYE_MCP_ROOT is a user-owned workspace by contract (ADR 0010), where that does
    // not hold. That boundary is stated, not silently assumed.

    // The child's whole environment: a minimal set (execve, no inheritance) so a
    // config's operation cannot read the server's credentials. PATH is needed to find
    // the target's argv[0] and strace-free helpers; nothing else is passed.
    const min_path = if (posix.getenv("PATH")) |p| std.mem.span(p) else "/usr/bin:/bin";
    const env = [_][2][]const u8{.{ "PATH", min_path }};

    // The oracle path is operational config (a trusted strace path), not model input —
    // it comes from the environment like the shim, and completes the account so a real
    // FAIL (and its saved case) can be reached rather than always UNKNOWN.
    const oracle = if (posix.getenv("SIDEEYE_MCP_ORACLE")) |o| std.mem.span(o) else null;
    var argv_buf: [16][]const u8 = undefined;
    var argc: usize = 0;
    const base: []const []const u8 = switch (kind) {
        .explore => &.{ self, "explore", "--config", path },
        .replay => &.{ self, "replay", path },
    };
    for (base) |a| {
        argv_buf[argc] = a;
        argc += 1;
    }
    // `--work` points at the server work dir so saved cases land under it (and, when
    // it is inside SIDEEYE_MCP_ROOT, are replayable through this same server). `--json`
    // is where this call's report goes.
    for ([_][]const u8{ "--json", temp_json, "--shim", shim, "--work", work }) |a| {
        argv_buf[argc] = a;
        argc += 1;
    }
    if (oracle) |o| {
        argv_buf[argc] = "--oracle";
        argv_buf[argc + 1] = o;
        argc += 2;
    }
    const argv = argv_buf[0..argc];
    // Minimal-env self-exec with the child's stdout captured to a file — fd 1 (the MCP
    // transport) stays clean.
    const term = posix.runChildCaptureMinimalEnv(gpa, argv, &env, child_out) catch
        return emitToolError(arena, id, "could not run sideeye");
    const exit_code: i64 = switch (term) {
        .exited => |c| c,
        else => -1,
    };
    // 126/127 are the fork stub's own exit codes (capture could not open / exec
    // failed) — sideeye itself exits 0..3. Neither leaves a report for this call, so
    // anything found at the report path would be somebody else's file; say what broke
    // instead of reading it.
    if (exit_code == 126) return emitToolError(arena, id, "the child could not open its stdout capture in the work directory");
    if (exit_code == 127) return emitToolError(arena, id, "self-exec failed: the canonical sideeye binary could not be executed");

    const report = readFile(arena, temp_json, 4 * 1024 * 1024) orelse
        return emitToolError(arena, id, "sideeye produced no report (or a report over 4 MiB)");
    const report_min = minifyJson(arena, report) orelse
        return emitToolError(arena, id, "sideeye produced an unparseable report");

    // isError distinguishes "the tool ran and reported a verdict" from "fix your input
    // or environment and retry" (spec). A crash-consistency FAIL/PASS is a real verdict
    // (isError:false); everything else asks the caller to act (isError:true).
    const is_error = isActionable(arena, report_min);
    const summary = summarize(arena, report_min) orelse report_min;

    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    appendId(arena, &out, id);
    out.appendSlice(arena, ",\"result\":{\"resultType\":\"complete\",\"content\":[{\"type\":\"text\",\"text\":") catch return;
    appendJsonString(arena, &out, summary) catch return;
    out.appendSlice(arena, "}],\"structuredContent\":") catch return;
    out.appendSlice(arena, report_min) catch return;
    out.appendSlice(arena, ",\"isError\":") catch return;
    out.appendSlice(arena, if (is_error) "true" else "false") catch return;
    out.appendSlice(arena, "}}") catch return;
    emit(out.items);
}

var counter: u64 = 0;

fn strArg(args: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    return switch (args.get(key) orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => null,
    };
}

fn emitResult(arena: std.mem.Allocator, id: std.json.Value, body: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    appendId(arena, &out, id);
    out.appendSlice(arena, ",\"result\":{") catch return;
    out.appendSlice(arena, body) catch return;
    out.appendSlice(arena, "}}") catch return;
    emit(out.items);
}

fn emitError(arena: std.mem.Allocator, id: std.json.Value, code: i64, message: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    appendId(arena, &out, id);
    var nb: [24]u8 = undefined;
    out.appendSlice(arena, ",\"error\":{\"code\":") catch return;
    out.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{code}) catch return) catch return;
    out.appendSlice(arena, ",\"message\":") catch return;
    appendJsonString(arena, &out, message) catch return;
    out.appendSlice(arena, "}}") catch return;
    emit(out.items);
}

/// A tool execution error (isError:true) — actionable feedback the model can retry on,
/// distinct from a protocol error (JSON-RPC error).
fn emitToolError(arena: std.mem.Allocator, id: std.json.Value, message: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    appendId(arena, &out, id);
    out.appendSlice(arena, ",\"result\":{\"resultType\":\"complete\",\"content\":[{\"type\":\"text\",\"text\":") catch return;
    appendJsonString(arena, &out, message) catch return;
    out.appendSlice(arena, "}],\"isError\":true}}") catch return;
    emit(out.items);
}

/// Echo the request id. PoC: integer or string; other shapes become null.
fn appendId(arena: std.mem.Allocator, out: *std.ArrayList(u8), id: std.json.Value) void {
    switch (id) {
        .integer => |i| {
            var nb: [24]u8 = undefined;
            out.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{i}) catch "null") catch {};
        },
        .string => |s| appendJsonString(arena, out, s) catch {},
        else => out.appendSlice(arena, "null") catch {},
    }
}

/// Minimal JSON string escaping (control bytes + quote + backslash). Mirrors main.zig's
/// jsonString discipline; kept local so mcp.zig has no cross-module private dependency.
fn appendJsonString(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(arena, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(arena, "\\\""),
            '\\' => try out.appendSlice(arena, "\\\\"),
            '\n' => try out.appendSlice(arena, "\\n"),
            '\r' => try out.appendSlice(arena, "\\r"),
            '\t' => try out.appendSlice(arena, "\\t"),
            else => if (ch < 0x20) {
                var nb: [8]u8 = undefined;
                try out.appendSlice(arena, std.fmt.bufPrint(&nb, "\\u{x:0>4}", .{ch}) catch unreachable);
            } else try out.append(arena, ch),
        }
    }
    try out.append(arena, '"');
}

/// The realpath'd server root; tool paths must resolve inside it.
var server_root: []const u8 = "";
var root_buf: [contract.max_path]u8 = undefined;

/// realpath a directory into a stable buffer; null if it does not resolve.
fn resolveDir(dir: []const u8) ?[]const u8 {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{dir}) catch return null;
    if (posix.realpath(z.ptr, &root_buf)) |p| return std.mem.span(p);
    return null;
}

/// Resolve a tool-supplied path and require it to live inside `server_root`. Uses
/// realpath (so `..`, symlinks and relative spellings are all collapsed first), then a
/// component-boundary prefix check — `/root` must not match `/rootother`. Returns the
/// resolved absolute path, or null if it does not exist or escapes the root.
fn resolveInsideRoot(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return null;
    var rp: [contract.max_path]u8 = undefined;
    const resolved = posix.realpath(z.ptr, &rp) orelse return null; // must exist
    const r = std.mem.span(resolved);
    if (!std.mem.startsWith(u8, r, server_root)) return null;
    // Boundary: exactly the root, or the next byte is a path separator.
    if (r.len != server_root.len and r[server_root.len] != '/') return null;
    return arena.dupe(u8, r) catch null;
}

/// Whether the result asks the caller to act (isError:true) rather than reporting a
/// real verdict. Read structurally from the report's `verdict` field: PASS and FAIL
/// are verdicts; everything else (every UNKNOWN, SETUP_ERROR) needs the caller to fix
/// the input, the environment, or the expectation. The first version matched a fixed
/// list of unknown_reason substrings instead, and every reason missing from the list
/// rode through as isError:false — measured live with no_shim_marker, which an agent
/// would have read as a settled verdict. A fixed-string guard is silently void the
/// day the string is absent; the verdict field is the structural property. Reports
/// that cannot be parsed or carry no verdict are actionable (fail closed).
fn isActionable(arena: std.mem.Allocator, report_min: []const u8) bool {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, report_min, .{}) catch return true;
    if (parsed != .object) return true;
    const verdict = strField(parsed.object, "verdict") orelse return true;
    return !(std.mem.eql(u8, verdict, "PASS") or std.mem.eql(u8, verdict, "FAIL"));
}

test "isError derives from the verdict field, not a reason list" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The live repro: an UNKNOWN whose reason no fixed list mentioned must still be
    // actionable — this is the case the substring version answered isError:false to.
    try std.testing.expect(isActionable(a, "{\"verdict\":\"UNKNOWN\",\"unknown_reason\":\"no_shim_marker\"}"));
    try std.testing.expect(isActionable(a, "{\"verdict\":\"SETUP_ERROR\"}"));
    try std.testing.expect(!isActionable(a, "{\"verdict\":\"PASS\"}"));
    try std.testing.expect(!isActionable(a, "{\"verdict\":\"FAIL\"}"));
    try std.testing.expect(isActionable(a, "not json")); // fail closed
    try std.testing.expect(isActionable(a, "{\"schema\":\"sideeye/report\"}")); // no verdict: fail closed
}

/// Best-effort unlink for a work-dir artifact this server is about to recreate.
fn unlinkPath(path: []const u8) void {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return;
    _ = posix.unlink(z.ptr);
}

/// A human-readable content summary for the agent (spec recommends a text block beside
/// structuredContent). Pulls the fields §17's second-criterion agent needs to act:
/// verdict, the reason/message, and the replay handle. Null if the report cannot be
/// parsed (the caller falls back to the raw minified report).
fn summarize(arena: std.mem.Allocator, report_min: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, report_min, .{}) catch return null;
    if (parsed != .object) return null;
    const o = parsed.object;
    const verdict = strField(o, "verdict") orelse "?";
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, verdict) catch return null;
    if (strField(o, "unknown_reason")) |r| {
        out.appendSlice(arena, " (") catch return null;
        out.appendSlice(arena, r) catch return null;
        out.appendSlice(arena, ")") catch return null;
    }
    if (strField(o, "message")) |m| {
        out.appendSlice(arena, ": ") catch return null;
        out.appendSlice(arena, m) catch return null;
    }
    if (strField(o, "case")) |c| if (!std.mem.eql(u8, c, "(none)")) {
        out.appendSlice(arena, "\ncase: ") catch return null;
        out.appendSlice(arena, c) catch return null;
    };
    if (strField(o, "replay")) |rp| if (!std.mem.eql(u8, rp, "-")) {
        out.appendSlice(arena, "\nreplay: ") catch return null;
        out.appendSlice(arena, rp) catch return null;
    };
    return out.items;
}

fn strField(o: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    return switch (o.get(key) orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => null,
    };
}

fn emitUnsupportedVersion(arena: std.mem.Allocator, id: std.json.Value, requested: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    appendId(arena, &out, id);
    out.appendSlice(arena, ",\"error\":{\"code\":-32022,\"message\":\"Unsupported protocol version\",\"data\":{\"supported\":[\"2026-07-28\"],\"requested\":") catch return;
    appendJsonString(arena, &out, requested) catch return;
    out.appendSlice(arena, "}}}") catch return;
    emit(out.items);
}

/// Re-serialize a JSON document with no whitespace, so it fits on one JSON-RPC line.
/// Returns null if the input is not valid JSON (an unparseable report is a tool error,
/// not something to embed raw).
fn minifyJson(arena: std.mem.Allocator, src: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, src, .{}) catch return null;
    return std.json.Stringify.valueAlloc(arena, parsed, .{ .whitespace = .minified }) catch null;
}

/// Read a file, refusing at `cap` bytes. The report is target-influenced (its paths,
/// its stdout via l1/message), so an unbounded read is a memory-exhaustion surface;
/// the cap keeps a runaway report from taking the server down.
fn readFile(arena: std.mem.Allocator, path: []const u8, cap: usize) ?[]const u8 {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return null;
    const fd = posix.open(z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n < 0) return null;
        if (n == 0) break;
        list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
        if (list.items.len > cap) return null;
    }
    return list.items;
}
