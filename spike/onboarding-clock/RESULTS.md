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
  returning exit 0: `PASS`, 4 of 4 crash worlds (crash points 3 + baseline),
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
clock ran against the repaired artifact, sha-pinned in the Dockerfile.
