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

### Notes

- Targets that leave the supported boundary — raw syscalls, static linking, a hardened runtime, `fork`/`exec`, threads, or operations outside the modelled set — are reported UNKNOWN. They are never reported as passing.
- PASS requires a completeness check. Without one, the run ends UNKNOWN unless `--allow-unverified` is given.
- Configuration is by command-line flags in this release. The `sideeye.toml` contract described in DESIGN §12 arrives in v0.2, along with L1 success markers.
