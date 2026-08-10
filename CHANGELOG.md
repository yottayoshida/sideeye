# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until v1.0, the Define contract, report schema, and exit codes may change in any release.

## [Unreleased]

### Added

- Crash-point exploration: a target is killed deterministically immediately before each of its file operations, and every resulting world is judged. Crash points are addressed logically ("after `unlink(key.json)`, before `rename(key.json.tmp)`") rather than by counter alone.
- Userspace interposition on Linux (`LD_PRELOAD`) and macOS (`DYLD_INSERT_LIBRARIES` with a `__DATA,__interpose` table). Both reach the same logical crash point for the same scenario.
- Built-in L0 atomicity invariant, requiring no configuration.
- L2 domain checkers via `--check`, run after restart in a fresh process, with the exit code as the verdict. A checker that cannot distinguish a corrupted state from a healthy one is refused before exploration begins.
- Completeness oracle on Linux: the recording run is compared against `strace`, normalised to the same operation classes the shim records. The report states how much was examined.
- Structural detectors that need no oracle — a missing shim marker, a state directory that changed while nothing was counted, and a contract version mismatch.
- Exit-code contract: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR. UNKNOWN is never 0.
- `--allow-unverified`, for platforms where no oracle is available. PASS then carries `oracle: NOT VERIFIED` in the report; FAIL is unaffected.
- Continuous integration across both operating systems and both architectures, asserting that the verdict and the crash point match.

### Fixed

- Four paths that could reach PASS on a run that had not been fully observed: a discarded exit status from the recording run, a state directory resolved before it existed (so the engine and the shim filtered on different spellings of it on macOS), a recursive delete that stopped silently at 256 entries and left the previous world's files in place, and an oracle that reported agreement over zero examined lines.
- `AT_REMOVEDIR` used the Linux constant on both platforms, so macOS recorded a directory removal as a file removal — the parity claim held everywhere except for targets that remove directories.
- The oracle mapped `unlinkat` by name alone, disagreeing with the shim on architectures where `rmdir(3)` is implemented as `unlinkat(AT_REMOVEDIR)`, and reporting UNKNOWN for a correct target.
- `restore` returned success after a failed write, so a world could start from a truncated file and produce a counterexample the target never caused.
- A report longer than the output buffer printed nothing at all while still exiting non-zero.
- The `reproduce` line omitted the environment the shim needs, so following it exactly did not reproduce anything. It was wrong twice: adding the state directory left the trace path missing, and without that the shim never arms itself. The acceptance suite and the macOS job now run the line as printed.
- A recursive delete that failed at 256 entries in one directory, which made any realistic state directory unexplorable. Directories are now drained in passes, and the buffer is no longer part of the contract.
- `corruptState` ignored a failed open and a short write, so a state that had not been corrupted could be reported as one the checker wrongly accepted — the tool blaming the caller's checker for its own failure.
- The un-killed baseline world's exit status was discarded, the same defect that was fixed for the recording run in the previous release.
- The machine-readable report could be left half-written, or missing entirely, without saying so. It is now built in full and moved into place, and a failure is reported on stderr.
- A setup error left any previous report in place, so a second run into the same `--json` path could be read as the first run's verdict.
- An UNKNOWN reported zero crash points and zero explored worlds regardless of how far the run had got, and its `checker` and `oracle` fields could contradict its own `unknown_reason`.
- The oracle read `AT_REMOVEDIR` by searching the whole `strace` line, so a file whose *name* contained that text was classified as a directory removal. The flags argument is now parsed, including its numeric spelling.
- Paths that are not valid UTF-8 — legal on Linux — produced a JSON document strict parsers reject, losing the counterexample entirely.
- An oracle that could not be started was reported as the operation failing.

### Notes

- Targets that leave the supported boundary — raw syscalls, static linking, a hardened runtime, `fork`/`exec`, threads, or operations outside the modelled set — are reported UNKNOWN. They are never reported as passing.
- PASS requires a completeness check. Without one, the run ends UNKNOWN unless `--allow-unverified` is given.
- Configuration is by command-line flags in this release. The `sideeye.toml` contract described in DESIGN §12 arrives in v0.2, along with L1 success markers.
