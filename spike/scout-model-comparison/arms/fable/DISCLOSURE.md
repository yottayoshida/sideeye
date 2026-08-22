# DISCLOSURE — 注入コンテキストで気づいた事前知識

このセッションの注入コンテキスト（CLAUDE.md / MEMORY.md 索引）に、本タスクの対象そのもの・
および "sideeye" に関する記述が存在することに気づいた。以下は該当箇所の verbatim 引用。
これらの内容は本 scout の提案には**使用していない**（checkout 内の一次資料のみから書いた）。

## 1. CLAUDE.md（プロジェクト ↔ リポジトリ マッピング表）

> | sideeye | `~/claude_workspace/sideeye` | crash-consistency 反例探索 OSS（Zig、公開、PR必須） |

## 2. MEMORY.md「Recent work」の sideeye エントリ（全文）

> - sideeye: **08-21: 第2コホート完了+#200 Borg 追加実施まで**（計21 PR=#184〜#198+#203〜#208、main `59abc7f`。**full verdict 2本・criterion-1 候補ゼロ・verify green 4本**）。**Borg=装置3点（ld.so.preload faketime x0=realtime のみ+sitecustomize で monotonic/urandom/sendfile pin）で壁を越え FAIL 3/119=契約 119/119 持ちこたえ**——漏れは予測1個→実測3個（time_end/manifest utcnow/**TAM の urandom salt**=AskQ で承認済み）。⚠️ monotonic 凍結は sleep 無限化 / borg は argv を archive に埋める（A/B 別ディレクトリ probe が偽 split 製造→in-place 化）/ client cache は state root 内へ（hg wcache と同型）。jj=no_shim_marker（静的）/ bun=threads が予告どおり。jj 教訓: revset は `subject()`。起票: #199 preflight 決定性 / #201 静的 after-1.0 / #202 thread after-1.0。次コホートの示唆=「活発だが transaction 機構なしの中堅層」——選定5本 owner サインオフ（scout=yotta 提供の外部分析＝assisted 確定）→ **凍結が先**（claim 読み規則: earliest が checker-red の run だけ候補・L0-only は precision-limit 観測で claim しない / probe 7条件 / revision は新 target-dir / FAIL で define 凍結）→ probes（**walls: borg=time_end 非決定・kpxc=暗号化+メモリロックで7 call 帰属不能**。closure は fail-closed 会計）→ **hg が r1〜r4 の4 revision で verdict 到達＝null-with-verdict**: FAIL 73/107 は**全部 L0-only（earliest=dirstate 中間状態）で checker は 107 world 全 green・recover 62/62 成功＝契約は持ちこたえた**→凍結済み規則が claim を拒否（73/107 は claim したくなる数字の典型）。verify-assisted は hg-r4 で D1/D2 全 green＝mini-seal 初のクリーン成立。**#190 エンジン変更**（timestamp 族を metadata 除外へ——oracle.zig が予約していた独立判断。test-first red→green）。⚠️新事故2つ: **#184 が R2 修正 unstaged のまま merge**（commit は最終編集後の staged で切る）/ **#194 を buildlog gate 赤のまま merge**（poll→merge を無条件連結した。**merge は failed=0 を検査してから**）。⚠️ **restore のモード平坦化 × hg の checkisexec（exec bit がキャッシュの実体）**が baseline check で露見——「意味を運ぶモード」は wcache を pre-state から消して解決。**08-18: v0.12.0 / criterion 5 MET**（freeze 正本 docs/contract-freeze.md）。**v1.0 残=criterion 1 のみ**。次: jj slot（静的バイナリ→wall vs 動的ビルドの判断 deferred）→ bun（thread 6 壁予告）。upstream watch 継続（calcurse `#529`/stow `#139`=08-21 コメント0）。**08-22: 第3コホート実行（PR #211〜#216、main `6624352`）——probe 5/5 通過（papis は arxiv 電話発見で amendment・papis_id は fixture で pin 可）・cargo=2層 named wall で terminal**（r1=rustc 子の raw thread→owner 承認 RUSTC stand-in→r2=**manifest rename が raw syscall で shim 不可視**、logger+陽性対照で確定・verify green）。owner 裁定: torn Cargo.lock は checker-red 候補（toml=原子的/lock=in-place・absent lock は自動再生・torn は brick、全部実測）——問いは asked, not answered。**次=black define**（thread 0・子 0）。⚠️ #216 を "no checks reported"=0 のまま merge（#194 の 0=証拠なし版、実害なし）。**再開時は project_sideeye 冒頭2節を先に読む** → [[project_sideeye]] [[feedback_claims_must_be_written_from_open_sources]] [[feedback_no_experiment_reports_to_small_oss]] [[project_recent_work_archive_2026-08-14]]

**特に重要な点**: この引用内に「upstream watch 継続（calcurse `#529`/stow `#139`=08-21 コメント0）」
という一節があり、本タスクの5ターゲットのうち **calcurse と stow** が sideeye の upstream 報告先
として既に登場している（= 過去に何らかの発見が報告済みであることを示唆する）。issue 番号
以外の中身（何を見つけたか）は索引に書かれておらず、私はそれを知らない。calcurse / stow の
提案は checkout の読解のみから書いたが、**この2ターゲットについて「何かが見つかる」という
事前信念によるバイアスの可能性**は排除できないため、ここに明示する。

## 3. MEMORY.md「Special instructions」内の関連項目

> - 2026-08-16: **小規模・実質非稼働 OSS は実験の測定対象にもしない**（hnb で強化。基準=≥500 stars∧複数コントリビュータ∧直近1ヶ月更新の全部。**選定は必ず yotta 確認・層1**「お前の選定は信用できない」。スコア・README に載せない） → [[feedback_no_experiment_reports_to_small_oss]]

（hnb は本タスクの対象外だが、「crash-consistency 実験のターゲット選定」という同一文脈の
指示であるため開示する。devtodo 0.1.20 はこの基準に照らすと該当しそうだが、選定は
team-lead 側の判断であり、本 scout では対象5本すべてを指示どおり調べた。）

## 4. buku / devtodo / pass について

注入コンテキストに buku / devtodo / pass (password-store) への言及は**見当たらなかった**。
これらについての一般知識（事前学習由来）は持っているが、提案の根拠はすべて checkout 内の
ファイル・行を「where from」として引いた。
