# unmass — define (explored), expected to refuse at the recording

Debian description: "Extract game archive files"; `implemented-in::c++`,
`use::converting`/`use::compressing`, `works-with::archive`. Installed
0.9-8+b1 in the trixie image (arm64). Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

man unmass: "unmass is a tool to extract game archives. It supports the
following archive types: … Doom (WADs), … Quake 1, …"; `-e <archive file>
<file name> [...<file name>]` "Opens the archive and extract files";
EXAMPLES "Opens 'battle.lgp' and extracts file 'aabc.txt' … into current
directory". `unmass -modules` lists "pak PAK (Quake)" and "wad WAD (doom,
id)". Local-file state, documented non-interactive writer → define: the state
holds a Quake PAK written by `setup.sh` with python3 (the documented format —
a `PACK` header, a directory of 64-byte entries — carrying two small
members), and the operation extracts one of them into the state directory.
Extraction goes "into current directory", so the operation is `op.sh`: a `cd`
into the state directory, then `exec` of the program by absolute path (the
`cd` changes no state; the exec chain is followed, ADR 0018's amendment).

**Measured while authoring, and recorded before the sweep (container, 0.9-8+b1
on arm64):** `unmass -list` and `unmass -e` end in **Segmentation fault**
(exit 139) on every archive that could be built from the documented formats —
a Doom PWAD, the same bytes with the IWAD signature, and the Quake PAK this
define seeds — while `unmass -modules` runs. The input is written to the
formats' published layouts; the crash is the same on each, and the package is
a binary rebuild (`+b1`) of code from 2007 on an architecture it was not
written for. The define is committed as it is: the sweep's recording run will
end in the signal, the engine will refuse `recording_run_failed`, and that is
a target-origin UNKNOWN — the target cannot run its documented operation on
this platform — not a define-budget miss. No `expect-status.txt`: 139 is a
signal, not a convention.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
refused the first observed run **`recording_run_failed`** — "the operation
exited 1 during the recording run where 0 was expected". Outside the engine
the same `op.sh` (and `unmass -e`, `unmass -list` on the same PAK, with and
without the shim preloaded by hand) ends in the signal, exit 139; inside the
engine's recording the status the engine decoded was 1. Both are recorded
here; neither is the operation completing, and the define is left as it is.
Exit 2, no `first_accepted_recording`.
