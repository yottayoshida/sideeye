*This page holds every run, appended in order and never edited. Run 2
(2026-08-28) is below run 1.*

# The onboarding clock — run 1 (2026-08-17)

**4 minutes 22 seconds, README open to a real verdict. Criterion 6: met, on
the first measurement.**

## The number and where it comes from

- Start `2026-08-16T23:57:56.585Z` — the driver session's first timestamped
  event (`runs/run1/timeline.tsv`, line 4; lines 2-3 are the init and
  rate-limit events, which the stream leaves untimestamped). The protocol
  declared the start as "the init event's timestamp"; the instrument therefore
  uses the first event that carries one — a drift of the init latency, in the
  direction that *favors* a met (a later start), immaterial against 4:22 vs
  10:00 and disclosed here rather than absorbed.
- Stop `2026-08-17T00:02:18.624Z` — the tool result of
  `./sideeye explore --config /tmp/se/sideeye.toml --oracle /usr/bin/strace …`
  returning exit 0: `PASS`, 4 of 4 explored worlds (crash points 3 + baseline),
  the oracle agreeing on 3 operations, the checker falsified before the run.
  It is the single stop candidate the extractor found (`runs/run1/meta.json`,
  `stop_candidates`).
- Wall-clock: **4:22.039**. Protocol: `PROTOCOL.md` beside this page,
  committed before the run. Driver: `claude --safe-mode` headless
  (claude-opus-5, 28 turns), not told it was timed.

The committed evidence is `timeline.tsv` (every event, timestamped, projected
from the raw stream by `clock-audit.py` — the one transformation is the
driver's host home directory spelled `~`) and `meta.json`. The raw
`transcript.jsonl` stays out of the repository (it embeds host paths); the
projection is re-runnable from it, and the extractor is committed.

## The audit, including what it flagged

Predicates: no network or delegation tools (clean — none attempted), no reads
into this repository (clean), every machine-touching command a docker
invocation of the box. The extractor flagged three commands under a stricter
reading than the protocol's — it demanded the literal prefix
`docker exec onboarding-box`:

1. `docker cp check.sh onboarding-box:/tmp/se/check.sh && docker exec …` —
   a docker invocation of the box under the protocol's own wording.
2. `B64=$(base64 < check.sh …); docker exec onboarding-box …`
3. `B64=$(base64 < sideeye.toml …); docker exec onboarding-box …` — host-side
   base64 of files **the driver itself authored** into its empty scratch
   directory (their Write events are in the timeline, lines 110 and 127),
   piped into the box.

Adjudication, recorded rather than silently passed: the seal exists to keep
outside information from entering the run — the network, this repository,
prior knowledge of the target. All three commands move driver-authored bytes
*into* the box; nothing flowed the other way. On the repository-read
predicate, precision about what "clean" means: the extractor checks the
file-path keys of tool calls, so a Bash-side or relative-path read is outside
that predicate's sight — the conclusion rests on the committed timeline being
short enough to verify by eye (145 events, all committed; note heads truncate
at 160 characters, and the full commands re-project from the raw stream), not
on the predicate alone. The run stands. The protocol file itself stays byte-identical
to its pre-run commit — this paragraph, not that file, is where run 1's
adjudication lives: host-side authoring and transfer of the driver's own
files is inside the seal, and any future protocol revision that wants to say
so in the protocol restarts the run count per the protocol's own rule. The
extractor keeps its strict prefix check so the transfer pattern is always
surfaced for adjudication, never silent.

Two instrument gaps, disclosed: the protocol promised the target's installed
version "recorded" — run 1 carries it only in a truncated tool-result head in
the timeline (jrnl v4.6), not as a meta field (filed, #160); and during run 1
the extractor's denied-tool list named fewer tools than the launcher denies —
the rest were denied only at the CLI layer, and none was ever attempted. The
extractor has since been synced to the launcher's full list; re-projection of
run 1 is unchanged by it (the run's tool calls were Bash and Write only).

*Instrument note (2026-08-25, #160): the protocol has since gained its first
amendment, so three present-tense sentences on this page are true of run 1's
date rather than of the files beside it today. The protocol file is no longer
byte-identical to its pre-run commit. The extractor's strict prefix check was
replaced by a quote-aware predicate — the transfer pattern is still surfaced,
never silent, now under the name `audit_adjudicate`. And re-projecting run 1's
raw stream with the current extractor would yield the hardened classification
and field names (the raw stream lives outside the repository, so that
re-projection is not run or committed here); the extractor that produced the
committed `meta.json` is the one at this run's own commit in history. The run count restarted per the
protocol's rule; run 1's numbers and adjudication are unchanged.*

*Instrument note (2026-08-28): **one parenthetical above is withdrawn**, and the
sentence it supported is narrower than it reads. "(the run's tool calls were
Bash and Write only)" is not supported by anything committed. The extractor of
this run's date wrote **one row per event** and **overwrote that row's note with
each content block**, so a tool census taken from `timeline.tsv` counts the last
block of each of the 145 events, not the calls made — a `Bash` call followed by
another call in the same event leaves only the second in the record. The same
bound applies to "short enough to verify by eye": an eye reading 145 rows sees
at most one call per event, and the raw stream those rows project from is
gitignored and no longer on disk, so "the full commands re-project from the raw
stream" is no longer available for this run. The predicates themselves did run
per content block, so run 1's audit was not blind — but it had no notion of a
tool outside the declared allow-set, and the amendment of this note's date
records why that matters: `--allowedTools` was measured that day to grant rather
than confine. **Whether run 1's driver stayed inside its allow-set is unmeasured
and, without the raw stream, no longer measurable.** What is unaffected: the
wall-clock arithmetic, the stop candidate, and the adjudication of the three
flagged commands, all of which read fields the overwrite never touched. Also
superseded: "the extractor has since been synced to the launcher's full list" —
the extractor no longer keeps a list to sync, since the launcher passes the
strings it gave the CLI. run 1's numbers and adjudication are unchanged.*

## What the driver said, verbatim

Its closing report (the `result` event, in full):

> **PASS（exit 0）**。
>
> **使った define**（`/tmp/se/sideeye.toml`）: `[world] state = "/tmp/se/state"` / `setup = "/tmp/se/setup.sh"`（seed 3件の journal.txt を作る）/ `operation = "/usr/local/bin/jrnl --config-file /tmp/se/jrnl.yaml beta"`（1件追記）/ `check = "/tmp/se/check2.sh"` / `expected_status = "0"`。実行: `./sideeye explore --config ... --oracle /usr/bin/strace --shim ./libsideeye_shim.so --work /tmp/se/work --json ...`。結果: 4 worlds（crash point 3 + baseline）全部で不変条件が保たれた。oracle は 3 operations で shim の記録と一致。checker は事前の falsify（`jrnl reports 1 entries but the file holds 0`）を通った。jrnl は `atomic_write`（mkstemp → write → `os.replace`）で journal 全体を書き直すので、途中で殺されても journal.txt は旧内容のまま残る。
>
> **README で頼った所**: 3ステップの順番（demo → preflight → explore）。demo は exit 1 が成功という説明どおり FAIL を出してバイナリ+shim の疎通確認になった。preflight が `recording accepted` を返し、さらに「oracle なしだと PASS に `--allow-unverified` が要る」と警告してくれたので最初から `--oracle /usr/bin/strace` を付けた。checker の書き方は「ツール自身の主張と観測可能な現実を突き合わせる」という例に従って、jrnl の読み戻し件数 vs ファイル内の生の行数、＋操作前からあった 3 件の生存、にした。「見たことのない checker は信用しない」という記述があったので、先に truncate/garbage/削除で自分でも落ちることを確かめた。
>
> **外した / 見落とした所**: 「Command strings split on spaces, no quoting」を最初は軽く見ていて、entry 本文をスペース無しの 1 語（`beta`）にする必要があった。あと README の Example にある `--shim` / `--work` は Usage 側の説明には出てこないので、Example から拾った。tarball には `docs/` も `spike/` も入っていないので、README がリンクしている checker-cookbook 等は最初から参照できない（README だけで足りた）。最後に、この PASS には無視できない留保がある: sideeye は journal.txt を "history form"（追記型）と判定し、`not tested` に `appended tails` が入った。つまり組み込み atomicity は末尾の破れを見ていない。そこは自分の checker（件数一致 + seed 生存）が埋めている、という理解で PASS を受け取った。

## What the run taught about the README

Load-bearing and working: the three-step order, the demo-as-smoke-test
sentence, preflight's oracle hint, the checker philosophy and the
falsification discipline (the driver corrupted its own checker's world to see
it fail — from prose alone). Gaps the driver named: `--shim` and `--work`
appear only in the Example, not in the Usage bullets (filed as a README
candidate); the argv form was available for the spaced entry text but the
driver chose a one-word entry instead — the constraint was understood, the
addition unused. One protocol artifact, not a README gap: the box carries no
`docs/`, so relative links are dead there; a real user reads them on GitHub.

## What this measurement is not

One run, one driver, one target. It proves the path exists and was walked
once in well under the budget — not a distribution, not a promise about every
target class. The rehearsal that preceded it found the aarch64-linux release
artifacts of v0.9.0 and v0.10.0 broken on lesser CPUs than their builders'
(measured on Apple-Silicon Docker; the x86_64 artifact shares the
construction, presumed affected and unverified — BUILDLOG 2026-08-17); the
clock ran against the repaired artifact, sha-pinned in the Dockerfile *(as it
stood: the v0.10.0 tarball. The Dockerfile's pin moved to the current release
on 2026-08-25 — PROTOCOL.md's second amendment that day — so this sentence's
"the Dockerfile" is the file at run 1's commit, not the one beside it now.)*

---

# The onboarding clock — run 2 (2026-08-28)

The first run under the 2026-08-28 protocol, and the first taken with an audit
that enumerates the allowed tool names rather than a list of denied ones.

## The number and where it comes from

**2 minutes 55.707 seconds**, from the session's first timestamped event
(`05:02:01.672Z`) to the tool result carrying a real PASS on jrnl
(`05:04:57.379Z`). Both timestamps are in the committed `runs/run2/timeline.tsv`;
the wall-clock is their difference and is not hand-written. Under the
criterion's ten minutes, so: **met**.

The launcher's own stamp, new in this protocol, reads `05:01:59Z` — **2.672
seconds** before the first timestamped event. Run 1 had no way to see that gap
at all, because its init event carried no timestamp either and nothing else
recorded a start. At this size the gap changes nothing; the field exists so that
at nine minutes it would not have to be assumed.

The session ran on for another 37 seconds after the qualifying exploration
(`duration_ms` 212931, 24 turns) to write its closing paragraph. The criterion's
number is the first qualifying exploration, not the session.

The exploration: `./sideeye explore --config /tmp/se/sideeye.toml --oracle
/usr/bin/strace …` against jrnl v4.6, returning **PASS over 4 of 4 explored
worlds** — and the checker falsified first, in the same output: `falsify:
committed entry lost or mangled: 'seedalpha keeps its whole body' missing;
journal now holds ['sideeye-corruption-probe']`. A check that cannot fail is not
a check, and this one was shown failing before it passed.

Driver: `claude --safe-mode -p`, model `claude-opus-5[1m]`, CLI `2.1.250`,
prompt sha256 `f3252339585270854af97f5175ccb0c8757ff2598fc68b89adf8b8ba3b4174af`
(the prompt's access sentence became normative in the same amendment, so this
differs from run 1's).

## The audit, including what it flagged

`audit_void` is **empty**: no denied tool was attempted, and nothing reached
this repository. `audit_adjudicate` holds **four findings over two commands**,
both surfaced by the box predicate rather than by the new closed-world one.

1. `05:02:39.704Z` — a plain `docker exec onboarding-box sh -c '…'` whose
   argument contains `$(python3 -c …)`. The substitution expands **inside the
   box**. Surfaced because the audit cannot tell an inside substitution from an
   outside one and the protocol prefers a flag over silence. Inside the seal.
2. `05:04:39.495Z` — three findings for one command: the driver authored its
   `setup.sh`, `check.sh` and `sideeye.toml` **on the host** under `/tmp/sedef`,
   then moved each into the box with `base64 … | docker exec … base64 -d > …`.
   That is run 1's transfer idiom, character for character, and run 1's
   adjudication governs it: driver-authored bytes moving *into* the box are
   inside the seal; nothing flowed the other way.

**A prediction in the 2026-08-25 amendment was wrong, and this run is where it
shows.** That amendment expected a driver reaching for the transfer idiom to be
*refused* by the scoped allowlist until it re-derived in-box authoring, and told
a reader of run 2 to look for refused transfer attempts before treating a slow
number as a README verdict. There were none: the allowlist refuses nothing, as
the 2026-08-28 amendment records. The number is a README verdict with no
apparatus detour in it.

The other 21 of 23 commands are plain box invocations. Reads of jrnl's own
installed source under `/usr/local/lib/python3.11/dist-packages/jrnl/` are what
the prompt calls fair game — jrnl is the driver's tool.

## What the permission layer actually granted

New in this protocol, and the reason it was added: `meta.json` now records the
tool inventory the CLI reported at init, beside the policy the launcher
declared. They do not match.

| | |
|---|---|
| Declared allowed | **6** — `Bash`, `Edit`, `Glob`, `Grep`, `Read`, `Write` |
| Actually granted | **18** |
| Granted but never declared | `CronList`, `DesignSync`, `EnterWorktree`, `ExitWorktree`, `ListAgents`, `Monitor`, `NotebookEdit`, `ReportFindings`, `Skill`, `TaskOutput`, `TaskStop`, `ToolSearch` |
| Declared but not granted | none |
| Denied names that were granted | **none — all 11 absent** |

The `Cron` family splits exactly on the deny list: `CronList` was granted,
`CronCreate` and `CronDelete` were not. So `--disallowedTools` removes what it
names, and `--allowedTools` does not confine what it omits — measured from a
plain terminal on 2026-08-28, and now visible inside a run's own evidence
without anyone probing anything.

**The driver used only `Bash`, 23 times.** Twelve undeclared tools sat available
and none was touched, so nothing here needed the new predicate. That the
predicate exists is what makes the sentence checkable rather than hopeful.

## The box was not newly created, and what was measured about that

`docker run` **failed** — `Conflict. The container name "/onboarding-box" is
already in use` — and the run proceeded against a container created at
`02:10:51Z`, two hours and fifty-one minutes earlier. The launcher's own checks
(running, `--network=none`) passed, because they ask about the box's state
rather than its age. This is a departure from "re-runs use a fresh box" and is
recorded as one.

What was measured, rather than assumed:

- **Zero files inside the box changed** between its start (`02:10:52`) and the
  run (`05:01:59`). The control for that scan: **47 files** changed after
  `05:01:59`, so the query was live rather than vacuously empty. The box's clock
  is UTC, so the window means what it says.
- The driver's own first command, `ls -la /home/user/onboarding`, shows the
  directory at `Aug 28 02:10` — image build time, untouched.
- `README.md`, the release tarball, `jrnl --version` and jrnl's configuration
  are **byte-identical** between this box and a container started fresh from the
  current image, compared by sha256 after the run.
- The box's `README.md` is byte-identical to `README.md` at the commit this run
  measures.

The image *ID* differs from the current tag's — the same-day rebuild was fully
cached and still exported a new manifest — but the contents that matter are the
four above, and they match. **Adjudication: the box was not new and was
materially untouched, so the run stands.** The literal deviation is on the page
because a reader should not have to reconstruct it from a failed `docker run`
line in someone's terminal.

## What this measurement is not

One run is one measurement. It is not a distribution, and it does not say the
README is good — it says one context-free driver got from that README to a real
verdict on an external target in under three minutes, once, on this date.

It is also not comparable to run 1's 4:22 as a trend. Between them the protocol
was amended twice, the pinned artifact moved from v0.10.0 to v0.13.0, the prompt
gained a normative sentence, and the README changed across thirteen commits.
Two numbers under four different conditions are two measurements, not a series.
