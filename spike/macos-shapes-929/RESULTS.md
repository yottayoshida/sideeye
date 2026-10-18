# #929: three macOS target shapes — results

The three shapes `SELECTION.md` fixed, measured with the released **v1.15.0** `aarch64-macos` asset on GitHub's runners: macOS **14.8.9** (23J631) and **26.6.2** (25G83). On both, `sudo -n true` asked for no password, so no result below is a missing privilege. Every recording took 0 to 2 seconds, far inside #896's 90-second limit.

Each checker failed its deliberately broken control on both hosts, so each can fail. Whether each also passes an intact state was checked only locally, on macOS 15.3, before the runs, and that check is not recorded here; sed's was also seen passing on the runners, through its four explored worlds. No refused run below reached its checker. sed's checker compares the file through `$(cat …)`, which drops a trailing newline, so a file that lost only its last newline would pass; a process kill does not tear a write, and the unverified PASS is not counted, so no result turns on it.

The record of the measurement is `run2/`: Actions run 39100064767, at commit `c59a85a9`. `run1/` (run 39099602844, at `c7de9ff7`) is kept as the apparatus's own failure. Its measure script let two functions share one shell variable, so the oracle's explore never ran, and git's setup failed on its second use. The next commit fixed both; no target, command, invariant or control changed. The workflow and measure script in this tree differ from the ones run2 ran only in how the token reaches the installer, `pipefail`, the removed push trigger, and comments.

## The table

| Shape | Target | Host | `preflight --twice` | `explore --oracle-fs-usage` | `explore --allow-unverified` | Kind of refusal |
|---|---|---|---|---|---|---|
| 1. single-process CLI | GNU sed 4.10 (`gsed -i`) | 14.8.9 | accepted, 3 operations | UNKNOWN `unsupported_syscall_observed` | PASS 4/4 | engine: the witness's reader does not model `fstat64_extended` |
| 1. single-process CLI | GNU sed 4.10 | 26.6.2 | accepted, 3 operations | UNKNOWN `unsupported_syscall_observed` | PASS 4/4 | the same |
| 2. launches helpers | git 2.55.0 (`git gc`) | 14.8.9 | UNKNOWN `boundary_without_oracle` | UNKNOWN `boundary_without_oracle` | UNKNOWN `boundary_without_oracle` | engine, by design: macOS has no witness for a process boundary |
| 2. launches helpers | git 2.56.0 | 26.6.2 | UNKNOWN `boundary_without_oracle` | UNKNOWN `boundary_without_oracle` | UNKNOWN `boundary_without_oracle` | the same |
| 3. protected system executable | `/usr/bin/plutil` | 14.8.9 | UNKNOWN `recording_run_failed` | UNKNOWN `recording_run_failed` | UNKNOWN `recording_run_failed` | platform: dyld refuses the `arm64` shim in an `arm64e` image |
| 3. protected system executable | `/usr/bin/plutil` | 26.6.2 | UNKNOWN `recording_run_failed` | UNKNOWN `recording_run_failed` | UNKNOWN `recording_run_failed` | the same |

Homebrew installed git 2.55.0 on one runner and 2.56.0 on the other, so the two git rows are not the same build; #929 asked for a frozen version, and Homebrew's current formula was used instead. git's `gc` also read the runner's global configuration, which the setup and the checker did not.

Where #929's protocol stopped: it runs the oracle's explore only after an accepted preflight. That held for sed. git and plutil were refused at the preflight; their oracle runs go beyond the protocol, recorded to show the witness agrees. `preflight` takes no `--oracle-fs-usage`, so on macOS it can never accept a process boundary.

## What each refusal says

- **sed**: `fs_usage reported a call on the state directory that this version does not model: … fstat64_extended F=3 … gsed`. `fstat64_extended` is `fs_usage`'s spelling of an attribute read. `src/fsusage.zig` lists `fstat64` among the read-only calls but no `_extended` spelling. The same line appears on both hosts (#963).
- **git**: the report says a process other than the subject operated on the judged directory and that no oracle can account for it. `--allow-unverified` does not lift a boundary's refusal. Whether git called `F_FULLFSYNC` (#948) is not known: the run was refused at its boundary first.
- **plutil**: dyld terminates the image, `incompatible architecture (have 'arm64', need 'arm64e')`, and the engine reports signal 6. The next step names "a clean run exits its declared success status" as the limit, and suggests a SIGKILL refusing a signature, which is not what happened (#964). Apple platform binaries as a class are recorded in `docs/target-classes.md` from `/usr/bin/true` (2026-08-18, a build before v1.15.0): `no_shim_marker` on macOS 15, a dyld termination on 26. Locally, on macOS 15.3, plutil with v1.15.0 was refused `no_shim_marker`; that run is not part of this record.

## What is new here

GNU sed's in-place edit, `git gc` and `plutil` on macOS are in no earlier record. The class of Apple platform binaries was measured before, through `/usr/bin/true` on macOS 15 and 26; plutil itself, macOS 14 and v1.15.0 are new for that shape. `SELECTION.md` says plutil's wall was recorded on 15 and 26; that was a misreading of the class's row, corrected here, and the selection is left as it was committed.

## v1.15.0 against #929's v1.14.0

v1.15.0 carries no fix aimed at the refusals met here: the witness's reader, the process boundary, and dyld's architecture check. Its changes to code shared with macOS (directory renames, #892; the slot table, #901) do not touch these paths as far as read; the results are expected, not measured, to read the same on v1.14.0.

## Conclusion

On macOS, the current release judges **GNU sed's in-place edit only with `--allow-unverified`**: the witness refuses an attribute read it does not model. That is GNU sed's result, not every single-process tool's: the platform table's `gdd` probe, also from Homebrew, gets an oracle-verified FAIL. The release cannot judge a tool that starts helper processes, by design; git's refusal names Linux's `--oracle` as the next step, which was not measured here. It cannot judge an Apple platform binary, which will not load the shim.

**One next change**, supported by the same line on both hosts: model `fs_usage`'s `_extended` stat spellings as the read-only calls they are, then re-run the sed shape (#963).
