# Results — 2026-09-28 shipped-v170

The released v1.7.0, installed by the page's installer, run with the page's command
(`apparatus/run.sh`: `explore --config … --oracle /usr/bin/strace --json`, no `--observe`) on the
six candidates the owner signed off, all six of those that cleared the gate and the novelty
pre-scan. Timeline: `transcripts/timeline.txt`; the prediction was fixed at 00:21:28Z
(`transcripts/prediction.sha256` — a time this run wrote itself; git cannot confirm it, since the
first commit is after the explores. pint's `has_issues=false`, and phpcbf in its place, were found
before that time in a query that was not kept; `transcripts/stars.txt` repeats it at 00:22), the pre-scans ran 00:17–00:51Z (`transcripts/receipts/prescan-started.txt`), the explores
00:51–00:54Z.

## The six

| target | version | mode reached | verdict | earliest | what the interruption left | replay | evidence |
|---|---|---|---|---|---|---|---|
| nbqa `black nb.ipynb` | 1.9.1 | default | **FAIL** 1/13 | crash point 10 of 12 | `nb.ipynb` 260 bytes → **0**, and nbqa's temporary `nb…_nbqa_ipynb.py` left beside it | FAIL ×2 | rc 0 |
| standardrb `--fix a.rb` | 1.56.0 | default | **FAIL** 1/3 | crash point 2 of 2 | `a.rb` 40 bytes → **0** | FAIL ×2 | rc 0 |
| phpcbf `--standard=PSR12 a.php` | 4.0.4 | default | **FAIL** 1/3 | crash point 2 of 2 | `a.php` 39 bytes → **0** | FAIL ×2 | rc 0 |
| kubectl `config use-context b` | 1.37.1 | supervised, after revision 1 | **FAIL** 1/5 | crash point 3 of 4 | the kubeconfig 355 bytes → **0**, and `config.lock` left behind | FAIL ×2 | rc 0 |
| terraform `fmt` | 1.16.4 | supervised, after revision 1 | **FAIL** 1/3 | crash point 2 of 2 | `main.tf` 84 bytes → **0** | FAIL ×2 | rc 0 |
| sqruff `fix a.sql` | 0.40.0 | supervised, after revision 1 | **FAIL** 1/3 | crash point 2 of 2 | `a.sql` 31 bytes → **0** | FAIL ×2 | rc 0 |

Every one is the same shape: the rewritten file is opened with a truncating open, and a kill
between that open and the write leaves it empty, **with its old bytes nowhere in the state
directory** (`Old bytes elsewhere: no` in each evidence table). Each was found by the built-in
rule — the file existed before the operation, so it must hold its old bytes or its new ones
(`l0_judged_paths` names it in every report) — and each checker, falsified before the run
(`transcripts/checkers-seen-red.txt`), agreed. `oracle_verified` is true for five;
nbqa's is `oracle_verified_subject_only` (its child black's four operations placed, not compared).
`command_cwd` is in every report whose define declares one. Every version is the project's
latest release, read again at 01:19Z from each project's release channel
(`transcripts/latest-releases.txt`), so no re-measurement on a newer one was due.

Transcripts: `transcripts/<target>/` (default mode) and `transcripts/<target>-r1/` (revision 1),
each with the explore's text and JSON, both replays, and `sideeye evidence`'s Markdown. The case
each replay read is kept as `case-*.json` beside them.

## Revision 1 — the static three, and the sentence that did not send them anywhere

Run with the fixed defines, the three static targets did not reach supervised. Each refused
`no_shim_marker` in the default mode, as the gate had said — and the refusal was not the one the
prediction described:

```
UNKNOWN  no_shim_marker
         the trace carries no shim marker; the operation's first word names no path, so the OS
         resolved it through PATH and Sideeye did not
next        Check that --shim names the interposition library from this build and that nothing
            strips the preload from the target's environment.
```

(`transcripts/terraform/explore.txt`; kubectl and sqruff the same.) Named as a user names it —
`terraform fmt`, found on `PATH` — the operation's image is not one Sideeye resolved, so the
refusal is silent about linkage and keeps the shim step, **exactly as `docs/report-schema.md`
documents** ("a first word resolved through `PATH` … is silent about linkage and keeps the shim
step, which is the honest default rather than a diagnosis"). Nothing in it names
`--observe supervised`, and `run.sh`'s follow, which reads the detail line, did not fire.

**The prediction was wrong here, and so was the selection record's first draft.** Both said the
nine static candidates' default-mode detail names `--observe supervised`. That was read from the
two static *legs*, whose operations name `/bin/busybox` by absolute path, and was never checked on
the candidates — every one of which names its image bare, and every one of which got the PATH
sentence at the gate too (`transcripts/entry/<name>.preflight-default.txt`). `SELECTION.md` now
says what the candidates were told; `PREDICTION.md` is left as it was fixed.

Revision 1 is the one change the refusal points a user toward — name the image by path
(`apparatus/defines/<target>-r1/`, labelled in each `sideeye.toml`; seed and checker unchanged).
Then the refusal reads the image, says it is statically linked and ends *"on Linux 5.19 or later,
on aarch64 or x86_64, --observe supervised counts it from outside the process instead"*, while its
`next` line says *"This target does something Sideeye refuses by design"*. `run.sh` followed the
detail, once, and all three reached their FAIL under supervised with the oracle agreeing on every
operation.

What needed the path was the pointer, not the mode. **Supervised itself takes the bare name**: the
gate's supervised preflight ran `kubectl config use-context …` named bare and accepted 4
operations with the oracle agreeing (`transcripts/entry/kubectl.preflight.txt`), and the same for
the other eight. The FAILs above were measured on the revision-1 spelling; no explore under
supervised was run on the bare name. So v1.7.0 can carry a static target to a verdict from the
spelling a user writes, **but its default-mode refusal does not send the user there**: a bare name
gets a `--shim` step, and a path gets a `next` sentence that contradicts its own detail. Neither
names the flag that works; only the detail line on a path does. (`run.sh`'s follow greps the whole
of `explore.txt` for the flag, target output included, not only the detail line; it was seen not
firing on the bare names and firing on revision 1, and not tried against a target that prints the
string itself.) Recorded as found; the owner's ruling
(2026-09-28) is to change it in a pull request of its own, not here — this run changes no engine
code.

## Against the prediction

| | predicted | measured |
|---|---|---|
| kubectl | FAIL (not confident) | FAIL — under supervised, after revision 1 |
| terraform | FAIL (not confident) | FAIL — under supervised, after revision 1 |
| sqruff | FAIL (not confident) | FAIL — under supervised, after revision 1 |
| nbqa | a verdict (confident), which one not confident | FAIL |
| standardrb | FAIL (not confident) | FAIL |
| phpcbf | FAIL (not confident) | FAIL |
| the static three's route to supervised | the detail names it | only once the image is named by path |

nbqa is the one to read against its tracker: nbQA-dev/nbQA#542, *"Make mutations atomic"*, merged
2021-02-17, is in its pre-scan (`transcripts/receipts/nbQA-dev_nbQA.prescan.txt`) — its title only;
its diff was not read. What was measured is that the notebook 1.9.1 writes back is opened with a
truncating open.

## Novelty and reporting

The pre-scan (`spike/cohort4/novelty-prescan.sh`, both controls green in every receipt) ran on all
six trackers — and on laravel/pint's, which had been queued before pint was dropped and ran after
it (00:42Z) — **before the explores** (`transcripts/receipts/prescan-started.txt`) — the order rule 14 asks for, which the 2026-09-22 run
did not keep. No hit on any tracker is about an interrupted rewrite of the file these operations
write. terraform's hits about empty state files (hashicorp/terraform#17066, #23538) are
`apply`'s state, not `fmt`'s source. kubectl's kubeconfig is written by client-go, so its search
was repeated on kubernetes/kubernetes — **at 00:55Z, after the explores**, so this one search is
not a pre-scan; it is the novelty check a FAIL gets (`transcripts/receipts/kubernetes_kubernetes.kubeconfig.txt`,
terms joined with `+` after the first, space-separated attempt returned zero for five of six — the
trap the pre-scan's header names): lock files for concurrent writers (kubernetes/kubernetes#28034),
nothing about a torn write.

The owner's ruling (2026-09-28), by the 2026-09-22 commitizen rule — a file a formatter rewrites
is normally under version control, so the loss is recoverable:

- **kubectl: report in preparation.** A kubeconfig is not under version control and carries the
  cluster endpoints and credentials; losing it is not recovered from git. The project's
  contribution and LLM-use policies are read before any text is written.
- **terraform, sqruff, nbqa, standardrb, phpcbf: not filed** (`not_worth` in the funnel).

## Found in passing

- **The static leg `touch`** (a new empty file) refuses `state_changed_without_ops` under
  supervised, and so does coreutils' dynamic `touch` in the default mode, under `--observe
  syscalls` and under supervised — preflight exit 2 in all four (`apparatus/probe-touch.sh`,
  `transcripts/probe-touch.txt`; the first draft of that transcript printed a filter's exit code,
  not preflight's, and was replaced). An open that creates an empty file is not a recorded mutating
  operation in any of the three modes. Not supervised's; not filed.
- **One `run.sh` start failed to parse** — `Syntax error: Unterminated quoted string` at line 61,
  on kubectl, the first target, at 00:51:43Z (`transcripts/run-all.txt`); `timeline.txt`'s
  "kubectl done" at that second is that failed start. The same command re-run under `sh -x`
  parsed and ran (its trace was not kept); it did not recur on the eight later starts, and kubectl
  was run once more at 01:19Z with the committed `run.sh` (sha256 `107a5549…`, the bytes every run
  read — the file was last edited before 00:40), which is what `transcripts/kubectl/` holds
  (`transcripts/run-kubectl-rerun.txt`): the same refusal. Not explained.
