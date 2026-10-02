Title: 🐝 Issue: `tombi format` leaves the file empty when its write fails or the process is killed before the write

### Preflight

- [x] I have searched existing Issues and Discussions for related reports.
- [x] This is not only a request to add a JSON Schema for a third-party project. For that case, I will ask the target project and SchemaStore instead.

### Current behavior

`tombi format` empties the file before it writes the formatted text. If the write then fails (a full disk, a quota, `ulimit -f`) or the process is killed in between, the file is left at 0 bytes and its previous contents are gone.

```console
$ ( ulimit -f 0; tombi format --offline a.toml ); echo "exit $?"
File size limit exceeded
exit 153
$ wc -c < a.toml
0
```

In `rust/tombi-cli/src/app/command/format.rs` at `04c7394` the file is opened read-write (line 550), cut with `file.set_len(0)` (line 575), then written with `write_all` (line 448).

### Expected behavior

If the file cannot be rewritten, it keeps its previous contents (or holds the formatted ones), and the error is reported.

### Reproduction

1. `printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > a.toml`
2. Run the command above.
3. `wc -c < a.toml` prints `0`.

### Environment

- Tombi version: 1.7.0 (1.5.6 behaves the same)
- OS: Debian 13 (trixie), aarch64, in a container
- Editor or CLI: CLI
- Installation method: `tombi-cli-1.7.0-aarch64-unknown-linux-musl.tar.gz` from the release page

### Additional context

`ulimit -f 0` stands in for a write that fails after the truncation. Killing the process between the `ftruncate` and the `write` leaves the same empty file (reproduced twice). TOML files are usually in version control, but uncommitted edits are lost with the file.

One possible direction, not tried: write to a temporary file in the same directory and rename it over the original. That replaces the file, so its mode and a symlinked path would need care.

Not tested: a real full disk (`ENOSPC`), power loss, torn writes, other platforms.

Disclosure: I found this with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.
