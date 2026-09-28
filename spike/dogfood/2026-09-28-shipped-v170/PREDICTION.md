# Prediction — 2026-09-28 shipped-v170, written before any explore ran

Its sha256 and the time it was taken are in `transcripts/prediction.sha256`, recorded before
the first `run.sh`; this file is committed unchanged, so the two can be compared.

## What each verdict will be written as

As on 2026-09-22 (`../2026-09-22-shipped-v160/PREDICTION.md`), unchanged:

- **PASS** — recorded with `oracle_verified` or `oracle_verified_subject_only`, the crash-point
  count, the mode it was reached in, and whether `command_cwd` and `l0_judged_paths` are in the
  report. A PASS has no evidence bundle; "evidence not reached" is written for it.
- **FAIL** — definitive only when `sideeye replay` reproduces it twice, in the mode it was found
  in. Recorded with the earliest crash point, what the checker or the built-in rule said, the
  replay transcripts, and `sideeye evidence`'s Markdown. Then the upstream question, asked of
  the owner per target: the target's latest release first, then novelty, then worth.
- **UNKNOWN** — where the release stopped carrying the target, with the reason and the `next`
  sentence as printed, and the one follow `run.sh` takes.

## What is new in this run, and how it is read

The static targets — kubectl, terraform, sqruff — reach explore through a follow that did not
exist on 2026-09-22. The page's command (no `--observe`) refuses them `no_shim_marker`; every one
of the nine static candidates did so at the gate. That refusal's **detail** names
`--observe supervised` and its **`next` sentence does not** (it reads "This target does something
Sideeye refuses by design"). `run.sh` follows the detail, once. So a verdict under supervised is
the release carrying the target **only for a reader who reads the detail line**; the `next`
sentence alone would have stopped them. That is recorded as found, whatever the verdicts are.

## Expectations, stated so they can be wrong

Each of the six rewrites a file that exists before the operation, so the built-in rule judges it
(pre-or-post) and a checker written with the tool itself asks whether the tool can still read it.

- **kubectl `config use-context`** (Go, static, supervised): **FAIL** (not confident). client-go
  writes a kubeconfig with a whole-file write; if that is `os.WriteFile`, the open truncates in
  place. The gate saw 4 operations, which would fit a lock file, the open and the write.
- **terraform `fmt`** (Go, static, supervised): **FAIL** (not confident) — 2 operations at the
  gate, which is the shape of an open that truncates and one write.
- **sqruff `fix`** (Rust, static, supervised): **FAIL** (not confident) — 2 operations; Rust's
  `fs::write` is a truncating create.
- **nbqa `black`** (Python, dynamic, default mode): a verdict (confident); which one, not
  confident. 12 operations: it copies the notebook out, runs black on the copy, and writes the
  notebook back. The write-back is the one judged.
- **standardrb `--fix`** (Ruby, dynamic): **FAIL** (not confident) — 2 operations.
- **phpcbf** (PHP, dynamic): **FAIL** (not confident) — 2 operations; `file_put_contents`.

So: six verdicts, five of them FAIL. The number to watch is not the FAILs — a two-operation
formatter that truncates is the shape this project has recorded in more than six languages — but
whether the three static targets reach a verdict at all, which is what v1.7.0 changed.
