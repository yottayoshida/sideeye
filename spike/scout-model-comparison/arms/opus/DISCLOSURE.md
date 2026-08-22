# DISCLOSURE

I noticed prior knowledge in my injected context. Recording it verbatim before scouting, and I did not use any of it to form the proposals.

## 1. "sideeye" appears in my injected memory index

The file `~/.claude/projects/-Users-i-yoshida-claude-workspace/memory/MEMORY.md` was injected into my system context. It contains a long entry about a project called `sideeye`. Verbatim excerpt of the parts that mention sideeye or the target tools:

From CLAUDE.md (project instructions), the repo mapping table:

> | sideeye | `~/claude_workspace/sideeye` | crash-consistency 反例探索 OSS（Zig、公開、PR必須） |

From MEMORY.md, "Recent work" section:

> - sideeye: **08-21: 第2コホート完了+#200 Borg 追加実施まで**（計21 PR=#184〜#198+#203〜#208、main `59abc7f`。**full verdict 2本・criterion-1 候補ゼロ・verify green 4本**）。**Borg=装置3点（ld.so.preload faketime x0=realtime のみ+sitecustomize で monotonic/urandom/sendfile pin）で壁を越え FAIL 3/119=契約 119/119 持ちこたえ**——漏れは予測1個→実測3個（time_end/manifest utcnow/**TAM の urandom salt**=AskQ で承認済み）。⚠️ monotonic 凍結は sleep 無限化 / borg は argv を archive に埋める（A/B 別ディレクトリ probe が偽 split 製造→in-place 化）/ client cache は state root 内へ（hg wcache と同型）。jj=no_shim_marker（静的）/ bun=threads が予告どおり。jj 教訓: revset は `subject()`。起票: #199 preflight 決定性 / #201 静的 after-1.0 / #202 thread after-1.0。次コホートの示唆=「活発だが transaction 機構なしの中堅層」——選定5本 owner サインオフ（scout=yotta 提供の外部分析＝assisted 確定）→ **凍結が先**（claim 読み規則: earliest が checker-red の run だけ候補・L0-only は precision-limit 観測で claim しない / probe 7条件 / revision は新 target-dir / FAIL で define 凍結）→ probes（**walls: borg=time_end 非決定・kpxc=暗号化+メモリロックで7 call 帰属不能**。closure は fail-closed 会計）→ **hg が r1〜r4 の4 revision で verdict 到達＝null-with-verdict**: FAIL 73/107 は**全部 L0-only（earliest=dirstate 中間状態）で checker は 107 world 全 green・recover 62/62 成功＝契約は持ちこたえた**→凍結済み規則が claim を拒否（73/107 は claim したくなる数字の典型）。verify-assisted は hg-r4 で D1/D2 全 green＝mini-seal 初のクリーン成立。**#190 エンジン変更**（timestamp 族を metadata 除外へ——oracle.zig が予約していた独立判断。test-first red→green）。⚠️新事故2つ: **#184 が R2 修正 unstaged のまま merge**（commit は最終編集後の staged で切る）/ **#194 を buildlog gate 赤のまま merge**（poll→merge を無条件連結した。**merge は failed=0 を検査してから**）。⚠️ **restore のモード平坦化 × hg の checkisexec（exec bit がキャッシュの実体）**が baseline check で露見——「意味を運ぶモード」は wcache を pre-state から消して解決。**08-18: v0.12.0 / criterion 5 MET**（freeze 正本 docs/contract-freeze.md）。**v1.0 残=criterion 1 のみ**。次: jj slot（静的バイナリ→wall vs 動的ビルドの判断 deferred）→ bun（thread 6 壁予告）。upstream watch 継続（calcurse `#529`/stow `#139`=08-21 コメント0）。**08-22: 第3コホート実行（PR #211〜#216、main `6624352`）——probe 5/5 通過（papis は arxiv 電話発見で amendment・papis_id は fixture で pin 可）・cargo=2層 named wall で terminal**（r1=rustc 子の raw thread→owner 承認 RUSTC stand-in→r2=**manifest rename が raw syscall で shim 不可視**、logger+陽性対照で確定・verify green）。owner 裁定: torn Cargo.lock は checker-red 候補（toml=原子的/lock=in-place・absent lock は自動再生・torn は brick、全部実測）——問いは asked, not answered。**次=black define**（thread 0・子 0）。⚠️ #216 を "no checks reported"=0 のまま merge（#194 の 0=証拠なし版、実害なし）。**再開時は project_sideeye 冒頭2節を先に読む**

## 2. What that tells me about the targets, specifically

Two of my five targets are named in that text:

- **calcurse** — named as `calcurse #529` under "upstream watch 継続" (upstream watch continuing), with the note `08-21 コメント0` (no comments as of 08-21). This implies an upstream issue was filed against calcurse at some point by this project. I do not know from the text what `#529` is about.
- **stow** — named as `stow #139`, same sentence, same "upstream watch" framing, same "no comments" note.

`buku`, `devtodo`, and `pass` are **not** named anywhere in my injected context.

I also carry, from that same text, general methodology knowledge of the engine described in my task prompt (baseline recording refusal on nondeterminism, "walls" where syscall shims cannot attribute I/O, L0-only findings not being claimable, etc.) and knowledge that other tools — borg, hg, jj, bun, cargo, papis, keepassxc, black — were previously scouted by the same project.

## 3. How I handled it

- I did not look up, recall, or reason from what `calcurse #529` or `stow #139` might be. My calcurse and stow proposals below are derived only from reading the checkouts under `targets/`, and I cite file+line for each.
- I did not read anything under `~/claude_workspace`, and in particular nothing under `~/claude_workspace/sideeye`.
- I did not use network access, `gh`, WebFetch, WebSearch, or deepwiki.
- I did not execute any target binary, configure script, or make target.
- Caveat I cannot fully discharge: the prior text shapes *what kind of thing I look for* (cross-file transactions, fsck commands, timestamp nondeterminism). But that framing is also spelled out explicitly in my task prompt, so it is not private information; the target-specific findings are all freshly read and cited.

## 4. One more incidental note

My injected `CLAUDE.md` and `MEMORY.md` contain a large amount of unrelated project state for this user's workspace (other repos, PR numbers, feedback rules). None of it concerns buku, devtodo, or pass. I mention it only for completeness.
