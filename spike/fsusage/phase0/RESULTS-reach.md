# 測定3: macOS で判定まで到達できる対象の割合

日付: 2026-08-29 / 機械: macOS 15.3.1 (24D70), arm64, **SIP 有効**, APFS
sideeye 1.0.0 (trace contract v12, Homebrew) / 生の出力: `runs/*.txt`
母集団と選定基準は `SELECTION.md`（**走らせる前に**書いた）

## 結果: 到達 5 / 6

### subject（6本）

| ツール | 由来 | 言語/パッケージ | 到達 | 観測操作数 / 壁 |
|--------|------|----------------|------|----------------|
| timewarrior 1.10.0 | dogfood corpus（§18 較正対象） | C++ / brew | **到達** | 25 |
| calcurse 4.8.2 | dogfood corpus | C / brew | **到達** | 13 |
| abook 0.6.2 | dogfood corpus | C / brew | **到達** | 2 |
| sqlite3 3.53.4 | 状態を持つ単一プロセス CLI | C / brew | **到達** | 27 |
| gnupg 2.5.21 | 状態を持つ単一プロセス CLI | C / brew | **到達** | 63 |
| stow 2.4.1 | dogfood corpus | **Perl** / brew | 到達せず | `no_shim_marker` |

**到達した5本はいずれも 0 操作ではない**（2〜63）。「recording accepted, but nothing to
explore — 0 state-changing operations observed」の縮退ケースは1本も無い。

### 対照（3本。装置が測れているかの検査）

| 対照 | 期待 | 実測 | 判定 |
|------|------|------|------|
| 自作 toy（`spike/toys/toy.c`、adhoc,linker-signed） | **到達必須** | 到達（4 操作） | OK |
| gh 2.97.0（Go / brew） | `multiple_threads_detected` | `multiple_threads_detected` | **peer #390 と一致** |
| git（Command Line Tools、Apple 署名） | `no_shim_marker` | `no_shim_marker` | **peer #391 と一致** |

対照3本が全部期待どおりなので、到達率を報告してよい（`SELECTION.md` の規律）。

## 判定

`SELECTION.md` の目安は「到達が 1/3 未満なら順序見直し」。**5/6 = 83% で大きく超える。
Route C を継続する。**

## この測定が変えたこと

**問題の像が変わった。** peer が出荷版を素の利用者として触ったとき、実物2件（git / gh）が
どちらも手前で断られた。それを見て「macOS 利用者が最初に会うのは弱い PASS ではなく拒否」と
読んだ。ところが sideeye が設計対象にしている C CLI の corpus で測ると、**6本中5本が到達する**。

peer の2件は、たまたま両方とも塞がっているクラスだった（Apple 署名 / Go のスレッド）。
どちらの標本もランダムではない。ただしこちらの標本は、この道具が判定を出せると分かっている
種類から引いている。

つまり **macOS の「全滅」の実態は、到達の壁ではなく検証の壁**。到達した5本はすべて
`--allow-unverified` を付けないと PASS を出せない。Route C が狙っているのはそこ。

## 外した予測

**gnupg は子プロセス壁で止まると書いたが、止まらなかった。** `gpg --homedir X --check-trustdb`
は gpg-agent を起動しない経路らしく、63 操作を観測して到達した。予測を先に書いていたので
外れが分かった。別の gpg 操作（鍵生成など）なら agent を起動して結果が変わりうる。
**この行は「この操作で到達した」であって「gnupg は到達する」ではない。**

## 装置が捕まえた自分のミス（1回目の走行）

対照が仕事をした。1回目、`git-apple` は `recording_run_failed` を返した。peer の
`no_shim_marker` と違うので装置を疑い、生出力を読むと `fatal: not a git repository` ——
**`git init` を書いていなかった**。壁を測ったつもりで自分の段取りミスを測っていた。
`abook` も同じ形で、ldif に `objectclass` / `sn` が無く abook が入力を拒否していた。
どちらも直して再測定（`runs/*-g2.txt`）。

**`SELECTION.md` に「対照が期待どおり止まらなければ到達率を報告しない」と書いておかなければ、
1回目の 4/6 をそのまま報告していた。**

## `no_shim_marker` は壁の名前ではなくバケツ（2026-08-29 訂正）

**初稿では stow と git を同じ壁として並べ、stow の原因を「Perl だからカーネルが exec するのは
Apple 署名の perl」と書いた。これは測っていない推論だった。** peer（PR #398 で着地）の指摘:
`no_shim_marker` には静的リンク・library validation・hardened runtime・trace 不読が全部落ちる。

読み直した結果（`codesign -dv --verbose=2` と `file`。**この表は測定の後に読んだ値**で、
run 中に読んだものではない）:

| 対象 | 読めたフィールド | バケツの中身 |
|------|----------------|-------------|
| `/opt/homebrew/bin/stow` | `/usr/bin/perl5.34` を指す shebang を持つスクリプト | 自身は Mach-O ですらない |
| `/usr/bin/perl5.34`（stow の shebang 先） | `Platform identifier=16` / `Identifier=com.apple.perl5` / `flags=0x0(none)` | **platform 標識を持つ** |
| CLT の `git`（#391 の実測） | `flags=0x2000(library-validation)` / Platform identifier フィールド無し | **library-validation フラグを持つ** |

**同じトークンで止まった2本は、読めるフィールドが違う。** 集計で `no_shim_marker` を1つの壁と
して数えると、この違いが消える。

上の表は**フィールド値を述べたもので、原因を述べたものではない**（peer が #391 で確立した
語彙規則。platform 標識が非ゼロでも「Apple のバイナリだから阻止された」とは書かない——
endorsement を読んでいないため）。stow が止まった原因そのものは、こちらでは測っていない。

なお main（`a31e765`）の build は refusal の detail 行がどのフィールドを読んだかを述べるので、
再測定すればこの仕分けは出力から直接取れる。**この測定は 1.0.0（brew）で走らせたので、
その detail は出ていない。**

## 測っていないこと

- **preflight は「判定に到達できるか」の門であって、判定そのものではない。** kill の着地、
  world 側のプロセス境界、baseline の挙動、checker の反証は preflight では走らない
  （出力自身がそう書いている）。full explore が PASS/FAIL に届くかは別の問い
- 各ツール1操作ずつ。操作を変えれば壁も変わりうる（gnupg がその実例）
- この機械1台のみ。SIP 有効・APFS・arm64
- 母集団は 6 本。brew の 141 formula から「状態を持つ単一プロセス CLI」を選んだもので、
  ランダム抽出ではない
