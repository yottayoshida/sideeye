Title: `--prepend` leaves the changelog empty when its write fails or the process is killed before the write

### Is there an existing issue for this?

- [x] I have searched the existing issues

### Description of the bug

`git-cliff --prepend CHANGELOG.md` reads the file, re-creates it with `File::create` (which truncates it), and then writes the new section followed by the old text. If that write fails (a full disk, a quota, `ulimit -f`) or the process is killed in between, the changelog is left at 0 bytes. Whatever in it was not committed yet is gone.

`git-cliff/src/lib.rs`, lines 983-985 at `60e0be9` (the same in v2.14.2):

```rust
let changelog_before = fs::read_to_string(path)?;
let mut out = io::BufWriter::new(File::create(path)?);
changelog.prepend(changelog_before, &mut out)?;
```

### Steps To Reproduce

1. In a repository with one tag and one commit after it, with a `CHANGELOG.md` (57 bytes in my run).
2. `git-cliff --unreleased > /dev/null` once, so the update check's cache file already exists (otherwise the limit below hits that write first).
3. `( ulimit -f 0; git-cliff --unreleased --prepend CHANGELOG.md )` prints `File size limit exceeded`.
4. `wc -c < CHANGELOG.md` prints `0`.

`ulimit -f 0` stands in for a write that fails after the truncation. Killing the process between the truncating open and the write leaves the same empty file (reproduced twice).

### Expected behavior

If the changelog cannot be rewritten, it keeps its previous contents (or holds the new ones), and the error is reported.

### Screenshots / Logs

_No response_

### Software information

- Operating system: Debian 13 (trixie), aarch64, in a container
- Rust version: n/a (the `git-cliff` wheel from PyPI)
- Project version: 2.14.2

### Additional context

A changelog is usually committed, so this costs less than it would for a file that is not; the case that hurts is edits made by hand since the last commit.

One possible direction, not tried: write to a temporary file in the same directory and rename it over the original. That replaces the file, so its permissions and a symlinked path would need care.

Not tested: a real full disk (`ENOSPC`), power loss, other platforms, `--output`.

Disclosure: I found this with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.
