const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");
const engine = @import("engine.zig");
const capture = @import("capture.zig");
const files = @import("files.zig");
const report = @import("report.zig");
const refuse = @import("refuse.zig");
const defang = @import("defang.zig");
const cli = @import("cli.zig");
const controls_mod = @import("controls.zig");

const setupError = refuse.setupError;
const spawnFailure = refuse.spawnFailure;
const removeFile = files.removeFile;
const textShown = defang.textShown;
const say = report.say;

const LegRun = struct { term: posix.Term, legs: ?[]const controls_mod.Leg };

var unread_legs_buf: [contract.max_path]u8 = undefined;

// Not `/dev/null`: a checker that replaces or removes the file it is handed (`mv`, `rm -f`)
// would, run as root, replace or remove the system's.
pub fn unreadLegs(work: []const u8) []const u8 {
    const p = std.fmt.bufPrint(&unread_legs_buf, "{s}/legs.unread.txt", .{work}) catch setupError(.define_invalid, "path too long");
    clearLegs(p);
    return p;
}

// An empty directory a checker made at the path is removed too, or every later run would read it;
// one with something in it is left, and reads as unreadable.
fn clearLegs(p: []const u8) void {
    removeFile(p);
    var z: [contract.max_path]u8 = undefined;
    const pz = std.mem.printSentinel(&z, "{s}", .{p}, 0) catch return;
    _ = posix.rmdir(pz.ptr);
}

pub fn checkerEnv(state_abs: []const u8, legs_path: []const u8) [3][2][]const u8 {
    return .{ .{ "TOY_STATE", state_abs }, .{ contract.env.state_dir, state_abs }, .{ contract.env.legs, legs_path } };
}

fn termWords(arena: std.mem.Allocator, term: posix.Term) []const u8 {
    return switch (term) {
        .exited => |c| std.fmt.allocPrint(arena, "exit {d}", .{c}) catch "exited",
        .signaled => |sig| std.fmt.allocPrint(arena, "signal {d}", .{sig}) catch "signaled",
        .unknown => "ended in a way the engine could not read",
    };
}

fn termPassed(term: posix.Term) bool {
    return switch (term) {
        .exited => |c| c == 0,
        else => false,
    };
}

fn runLabelled(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, argv: []const []const u8, state_abs: []const u8, legs_path: []const u8, capture_name: []const u8, name: []const u8) posix.Term {
    const out = std.fmt.allocPrint(arena, "{s}/{s}", .{ args.work, capture_name }) catch setupError(.environment, "out of memory");
    removeFile(out);
    const term = posix.runChildCapture(gpa, argv, &checkerEnv(state_abs, legs_path), .{ .path = out, .stderr_too = true, .exclusive = true }, args.cwd) catch |e|
        spawnFailure(e, .exploring, "could not run a [controls] command or the checker after it");
    // Labelled on every line: unlabelled, a control's output would read as a world's.
    if (capture.readFileAllocCapped(arena, out, 1024 * 1024, .{ .no_follow = true })) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| if (line.len > 0) say("{s}: {s}\n", .{ name, textShown(arena, line) });
    }
    return term;
}

// `stem` is `baseline` or `control.<leg>`: a leg name holds no `.`, so no leg's files are the baseline's.
fn checkWithLegs(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, cargv: []const []const u8, state_abs: []const u8, stem: []const u8, name: []const u8) LegRun {
    const legs_path = std.fmt.allocPrint(arena, "{s}/{s}.legs.txt", .{ args.work, stem }) catch setupError(.environment, "out of memory");
    // Not a file left from the run before: its lines would be read as this run's.
    clearLegs(legs_path);
    const label = std.fmt.allocPrint(arena, "{s} checker", .{name}) catch setupError(.environment, "out of memory");
    const capture_name = std.fmt.allocPrint(arena, "{s}.check.txt", .{stem}) catch setupError(.environment, "out of memory");
    const term = runLabelled(gpa, arena, args, cargv, state_abs, legs_path, capture_name, label);
    return .{ .term = term, .legs = readLegs(arena, legs_path) };
}

fn readLegs(arena: std.mem.Allocator, legs_path: []const u8) ?[]const controls_mod.Leg {
    var z: [contract.max_path]u8 = undefined;
    const pz = std.mem.printSentinel(&z, "{s}", .{legs_path}, 0) catch return null;
    if ((posix.kindOfPathNoFollow(pz.ptr) catch return null) == .missing) return &.{};
    // `require_regular`, not the kind above: a FIFO put there after it was looked at would hold
    // a plain open forever.
    const text = capture.readFileAllocCapped(arena, legs_path, 64 * 1024, .{ .no_follow = true, .require_regular = true }) orelse return null;
    return controls_mod.parseLegs(arena, text) catch setupError(.environment, "out of memory");
}

fn redNames(arena: std.mem.Allocator, legs: ?[]const controls_mod.Leg) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (legs orelse &.{}) |l| if (l.red) out.append(arena, l.name) catch setupError(.environment, "out of memory");
    return out.items;
}

pub fn run(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, state_abs: []const u8, final: engine.Snapshot, cargv: []const []const u8, control_argvs: []const []const []const u8) report.PreflightControls {
    engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state before the [controls] baseline", state_abs);
    const base = checkWithLegs(gpa, arena, args, cargv, state_abs, "baseline", "control baseline");
    const base_word = controls_mod.baseline(termPassed(base.term), base.legs);
    const out = arena.alloc(report.PreflightControl, args.controls.len) catch setupError(.environment, "out of memory");
    for (args.controls, control_argvs, out) |c, cargv_ctl, *o| {
        o.* = .{ .leg = c.leg, .word = @tagName(controls_mod.Word.baseline_red), .control_exit = null, .checker_exit = null, .red = &.{} };
        // Not run under a red baseline: no control can be told apart from it.
        if (base_word != .none) continue;
        engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state before a control", state_abs);
        const name = std.fmt.allocPrint(arena, "control({s})", .{c.leg}) catch setupError(.environment, "out of memory");
        const stem = std.fmt.allocPrint(arena, "control.{s}", .{c.leg}) catch setupError(.environment, "out of memory");
        const ctl_capture = std.fmt.allocPrint(arena, "{s}.txt", .{stem}) catch setupError(.environment, "out of memory");
        const ctl_term = runLabelled(gpa, arena, args, cargv_ctl, state_abs, unreadLegs(args.work), ctl_capture, name);
        o.control_exit = termWords(arena, ctl_term);
        if (!termPassed(ctl_term)) {
            o.word = @tagName(controls_mod.Word.control_failed);
            continue;
        }
        const chk = checkWithLegs(gpa, arena, args, cargv, state_abs, stem, name);
        o.word = @tagName(controls_mod.control(base.legs orelse &.{}, c.leg, termPassed(chk.term), chk.legs));
        o.checker_exit = termWords(arena, chk.term);
        o.red = redNames(arena, chk.legs);
    }
    engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state after the [controls]", state_abs);
    return .{
        .baseline = .{ .word = @tagName(base_word), .checker_exit = termWords(arena, base.term), .red = redNames(arena, base.legs) },
        .controls = out,
    };
}

pub const WorldChecker = struct { failed: bool, out: ?[]const u8 };

pub fn runWorldChecker(gpa: std.mem.Allocator, arena: std.mem.Allocator, cargv: []const []const u8, state_abs: []const u8, work: []const u8, cwd: ?[]const u8, out_buf: *[contract.max_path]u8, label: []const u8) WorldChecker {
    var out: ?[]const u8 = null;
    var capture_opened = true;
    const co = std.fmt.bufPrint(out_buf, "{s}/checker-output.txt", .{work}) catch
        setupError(.define_invalid, "path too long");
    // `exclusive` needs the removal, and without `O_EXCL` a FIFO planted at the name
    // would block the parent's open — the pair `Capture.exclusive` asks for by name.
    files.removeFile(co);
    // stderr too, for the reason #483 gives on the setup capture: a checker reports
    // through either stream, and capturing stdout alone would leave the file empty for
    // the ordinary failure.
    const ct = posix.runChildCapture(gpa, cargv, &checkerEnv(state_abs, unreadLegs(work)), .{ .path = co, .stderr_too = true, .exclusive = true }, cwd) catch |e| switch (e) {
        // The one failure that is about the capture and not about the child: since
        // #469 the parent opens the file, so this arrives before any child exists.
        // The checker still has to run — the verdict rests on its exit status — so
        // it runs uncaptured and the bundle's diagnostic stays unknown. Refusing
        // here would turn a FAIL into an UNKNOWN over an attachment.
        error.CaptureUnavailable => blk_cap: {
            // Left null on this path deliberately, rather than relying on the
            // removal above to make the read come back empty: "there is no capture"
            // and "the capture is empty" are different answers, and only the first
            // is true here.
            capture_opened = false;
            break :blk_cap posix.runChild(gpa, cargv, &checkerEnv(state_abs, unreadLegs(work)), cwd) catch |e2| spawnFailure(e2, .exploring, "could not run --check");
        },
        else => spawnFailure(e, .exploring, "could not run --check"),
    };
    // Set whichever way the child ended: a checker killed by a signal has often
    // written the line that says why, and the capture is what holds it.
    if (capture_opened) {
        out = co;
        // Not printed bare: `spike/acceptance.sh` counts gate lines, world lines and unmarked
        // checker lines, which must be none.
        if (capture.readFileAllocCapped(arena, co, 1024 * 1024, .{ .no_follow = true })) |text| {
            var lines = std.mem.splitScalar(u8, text, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                say("{s}: {s}\n", .{ label, line });
            }
        }
    }
    return .{ .out = out, .failed = switch (ct) {
        .exited => |code| code != 0,
        else => true,
    } };
}
