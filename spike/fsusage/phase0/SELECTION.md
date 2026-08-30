# 測定3 の母集団と選定基準（走らせる前に書く）

日付: 2026-08-29 / 機械: macOS 15.3.1 (24D70), arm64, SIP 有効 / sideeye 1.0.0 (brew)

## 問い

照合儀式（`attest`）は「判定まで到達したが主張が弱い」対象しか救わない。
**判定に到達する対象がどれだけあるのか**を、作る前に測る。

## 選定基準（この順で適用）

1. **sideeye が Linux で実際に判定を出した corpus を最優先**する。`docs/target-classes.md`
   の「Measured, with verdicts」表に載っている行が出発点。理由: 「この道具が判定できる種類の
   ツール」の定義がそこにあり、それが macOS で到達するかが答えるべき問い。ランダムな
   brew formula は「状態を持たない」で落ちるだけで、macOS 固有の壁を測れない
2. **既に installed のもので、状態をディレクトリに持ち、状態変更操作を1つ名指しできるもの**を足す
3. **既知の壁の対照を2本入れる**。peer が実測した `gh`（Go / brew / スレッド壁）と
   Apple 署名の `git`（library validation 壁）。**これが緑になったら測定装置側の異常**
4. 除外: TUI（端末が要る）／サーバー型（tmux, zellij, ttyd）／実クレデンシャルストアに触るもの
   （`lkr` — security.md の層1）／システムを更新するもの（`topgrade`）

## 母集団（N = 9）

| # | ツール | 由来 | 言語/パッケージ | 入っているか | 選んだ理由 |
|---|--------|------|----------------|-------------|-----------|
| 1 | timewarrior | dogfood corpus | C++ / brew | 要 install | §18 の較正対象。Linux で FAIL を発見した当のツール |
| 2 | calcurse | dogfood corpus | C / brew | 要 install | Linux で FAIL 1/11、upstream 報告済み |
| 3 | abook | dogfood corpus | C / brew | 要 install | Linux で null（3操作・違反0）。到達はした |
| 4 | stow | dogfood corpus | Perl / brew | 要 install | Linux で FAIL 2/5。**macOS では interpreter 経路が予想される** |
| 5 | omamori | dogfood corpus | Rust / brew | 済 | Linux で PASS 143/143 |
| 6 | sqlite3 | 基準2 | C / brew | 済 | 状態が1ファイル。単一プロセスの C として最も素直 |
| 7 | gnupg | 基準2 | C / brew | 済 | GNUPGHOME に状態。agent を起動するので子プロセス壁が予想される |
| 8 | gh | **対照** | Go / brew | 済 | peer 実測: `multiple_threads_detected`。再現しなければ装置異常 |
| 9 | git (CLT) | **対照** | Apple 署名 | 済 | peer 実測: `no_shim_marker`（library validation）。同上 |

## 期待する出力（先に書く。否定形も）

- 各本: `到達`（`recording accepted` / exit 0）または `壁の名前 + exit code`
- 集計: `到達 k / 9`、内訳を `multiple_threads_detected` / `no_shim_marker` /
  `child_process_detected` / `state_changed_without_ops` / その他 で数える
- **対照2本は必ず壁で止まる**。#8 が `multiple_threads_detected`、#9 が `no_shim_marker`。
  どちらかが到達したら、そこで止めて装置を疑う
- **stow は interpreter 経路で止まると予想**（`#!/usr/bin/perl` → Apple 署名）。
  もし到達したら予想が外れたということなので、その事実を記録する

## 判定の目安（先に置く）

- 到達が **9 の 1/3 未満（3本未満）**なら、Route C の順序見直しを yotta に上げる
- 到達が 3 本以上なら Route C を継続する
- **対照が期待どおりに止まらなかった場合は、到達率を報告しない**（装置が測れていない）

## 測り方

- `sideeye preflight --state <tmpdir 内の state> --operation "<絶対パス> <状態変更操作>"`
- state は毎回新しいディレクトリ。setup が要るものは `--setup` を付ける
- 生の出力を全部残す（`runs/` 配下）。要約だけで判断しない
