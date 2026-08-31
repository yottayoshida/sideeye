# 測定2: mkstemp(3) の創成は macOS でも shim に見えないか

日付: 2026-08-29 / 機械: macOS 15.3.1 (24D70), arm64, SIP 有効
sideeye 1.0.0 (trace contract v12, Homebrew) / 生の出力: `runs/mkprobe*.txt`
装置: `mkprobe.c`（この測定のために書いた。差が創成手段だけになるよう作った）

## 答え: 見えない。Linux (#39) と同じ

## 測り方

同一バイナリの2モード。**違いは創成が `open(2)` を通るか `mkstemp(3)` の内側かだけ**で、
その後の「13 バイト書いて閉じる」は両モードで同一のコード。

| モード | 創成 | 書き込み |
|--------|------|---------|
| `open` | `open(O_CREAT\|O_RDWR\|O_EXCL, 0600)` ← **陽性対照** | `write(fd, 13)` |
| `mkstemp` | `mkstemp(tmpl)` | `write(fd, 13)` — 同一行 |

前提を先に確認: 素で走らせて両モードとも 13 バイトのファイルが実際にできること（確認済み）。

## 結果

| モード | preflight の観測 | できたファイル |
|--------|-----------------|---------------|
| `open` | **2** state-changing operation(s) | `via-open` / 13 bytes |
| `mkstemp` | **1** state-changing operation(s) | `via-mkstemp-49zbdd` / 13 bytes |

差はちょうど 1。open モードの2つは `open` と `write`、mkstemp モードの1つは `write` だけ。
**`mkstemp` が内部で発行する `open` は shim に届いていない。** 陽性対照は同じ run の中にある
——書き込みは両モードで見えており、見えていないのは創成だけ。

これは Linux の #39（`spike/cohort4/mkstemp-class.txt`、Debian/glibc/strace）と同じ結論で、
macOS では初めての実測。ADR 0005 が「dyld interposition は libSystem 内部呼び出しに等しく
盲目」と測っていた推論が、mkstemp について確認された。

## 設計への帰結

設計プランの**反証可能チェック2の題材は mkstemp toy でよい**（stdio 経路への差し替えは不要）。
照合儀式が捕まえるべき「shim に見えない状態変更」の実例として macOS で成立する。

## 外した予測と、その原因

**書き込みを外したモード（`PROBE_NOWRITE=1`）で、両モードとも `state_changed_without_ops`
で拒否された。** open モードは創成が見えているのだから 1 操作が残ると予測していた。外れ。

原因は `docs/adr/0003-what-counts-as-a-crash-point.md` にそのまま書いてあった:

> `OpClass.open` has never counted toward `isMutation()` (excluding it makes
> `state_changed_without_ops` stricter) — so a target whose **only** state change is
> creating files via open is refused by that structural detector

つまり**同じ run について2つの数え方が動いている**。

- **アドレス可能な操作**（= crash point、preflight が数える「state-changing operation(s)」）
  には write-capable な `open` が入る
- **変更操作**（`isMutation()`、`state_changed_without_ops` が数える）には `open` は入らない

私は前者の数え方で後者の結果を予測していた。**この食い違いは上の主結果を否定しない**
——主結果は前者の数え方の中での 2 対 1 の差で、書き込みが両モードにある条件で測っている。

## 測っていないこと

- mkstemp 以外の族（`mkdtemp` / `tmpfile` / `dprintf`）。#39 が挙げている残りのメンバーは
  macOS で未測定のまま。Linux では `dprintf` と `tmpfile` が測られている
- oracle との突き合わせはしていない（macOS に非特権 oracle が無いのがそもそもの前提）。
  ここでの「見えない」は **shim の口座だけを読んで、同一 run 内の陽性対照と比べた**もの
- この機械1台のみ


## 追記 2026-08-31: oracle との突き合わせは、その後 CI に着地した

上の「測っていないこと」は**この 2026-08-29 の実験についての記述で、そのまま正しい**。
その後 `spike/fsusage/acceptance-local.sh` の Check 2 が同じ族の toy を実
`--oracle-fs-usage` に当て、CI の macOS job から毎回走っている。その leg が実際に
assert しているもの（見出しより狭い）は ADR 0035 に英語で書いた。
