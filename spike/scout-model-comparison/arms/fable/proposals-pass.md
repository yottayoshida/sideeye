# pass (password-store) 1.7.4 — scout proposals

## 1. 永続状態の所在
- `$PASSWORD_STORE_DIR`（既定 `~/.password-store`、`src/password-store.sh:15`）。中身は `*.gpg` のツリー ＋ 各階層の `.gpg-id`（＋任意で `.gpg-id.sig`、任意で store 自体が git repo）。
- 読み書き両方。編集用の平文一時ファイルは `/dev/shm` か TMPDIR（`password-store.sh:222,236`）で store 外。

## 2. 状態を書くコマンド
- 単一ファイル: `insert`（`$GPG -e -o "$passfile"` 直接出力、`:462,471,480`）、`generate`（新規は直接、`--in-place` は temp→`mv`、`:545-548`）、`edit`。
- **複数ファイル**:
  - `init <new-id>`: `.gpg-id` を上書き（`:348`）→ `reencrypt_path` が**配下の全 `*.gpg` を1つずつ** `gpg -d | gpg -e → temp → mv` で差し替え（`:110-140`、per-file の mv は `:136-137`）。ファイル数ぶんの I/O 境界を持つ store 全体トランザクション。
  - `mv old new`: `mv`（`:629`）→ 移動先の鍵集合が違えば `reencrypt_path`（`:630`）→ 空になった旧親ディレクトリを `rmdir -p`（`:644`）。
  - `rm`: `rm`（`:587`）→ `rmdir -p` で空親を掃除（`:594`）。
  - git 有効時は全変更コマンドが `git add`+`commit` を後置（man `pass.1:42-44`）＝ working tree と `.git` のクロスファイル。

## 3. ドキュメントの約束
- `man/pass.1:63-67`（init）: 「If the specified gpg-id is different from the key used in any existing files, **these files will be reencrypted to use the new id**.」→ init 後は配下の全ファイルが新 id で読める、が契約。
- `man/pass.1:157-158`（mv/cp）: 「Passwords are **selectively reencrypted to the corresponding keys of their new destination**.」→ 置き場所が受信者を決める、が契約。
- `man/pass.1:42-44`: git repo なら「all password store modification commands will cause a corresponding git commit.」
- `man/pass.1:144-145`（generate --in-place）: 「keeping the remainder of the file intact」。
- `man/pass.1:147-151`（rm）: 指定した pass-name を消す（それ以外は触らない、が含意）。

## 4. fsck / verify / undo
- 検査・修復コマンドは無し。undo は git 有効時の履歴のみ（`pass.1:42-48`）。`.gpg-id.sig` 検証は署名運用時だけ。

## 5. 決定性（重要・先に予告）
- **gpg で暗号化するあらゆる操作（insert / generate / edit / init の再暗号化 / 鍵集合が変わる mv・cp）は記録拒否を予想**。OpenPGP の暗号化はセッション鍵が毎回乱数で、出力バイトが毎回変わる（呼び出しは全て外部 `$GPG -e`、例 `:136,462`）。`generate` はさらに `/dev/urandom` から本文を作る（`:539-540`）。時刻 pin では消えず、gpg の決定化 shim（固定 session key / 固定乱数）が無い限り baseline が録れない。
- **決定的に録れる見込みがあるのは**: `rm`（rm+rmdir のみ）と、**鍵集合が変わらない** `mv`（`reencrypt_path` が current_keys==gpg_keys で再暗号化をスキップ `:132-137` → 実質 rename+rmdir）。git 無し fixture が前提（git commit はハッシュ・時刻で非決定）。
- 提案は「決定性の壁を越える価値が最も高い順」でランクし、壁は各提案に明記する。

## 提案（ランク順）

### P1: `init` による store 全体の鍵ローテーション
- **argv**: `pass init NEWKEY-ID`（環境: `PASSWORD_STORE_DIR=<state>`、fixture: OLDKEY で暗号化された `*.gpg` を 5〜10 件、git 無し。keyring は両鍵入りを engine 側 fixture として固定）
- **why**: `.gpg-id` 上書き（`:348`）の直後から、ファイルごとに「decrypt→encrypt→mv」を逐次実行（`:110-140`）。(a) `.gpg-id` 書き込み直後で切れば「宣言は新鍵・実体は全部旧鍵」、(b) ループ途中で切れば**新旧混在 store**。旧鍵を破棄する運用（鍵ローテの目的そのもの）では、混在＝**残った旧鍵ファイルの恒久喪失**。可用性でなくセキュリティ運用が壊れる、このターゲットで最も深い窓。
- **what property**: `pass.1:63-67` の契約——init 完了後、配下の**全** `*.gpg` の受信鍵が `.gpg-id` の内容と一致する。クラッシュ世界の checker は「各ファイルの受信鍵集合 ⊆ 支配する `.gpg-id` の鍵集合、または操作前の旧 `.gpg-id` との完全一致（未着手状態）」の二値のみ許容。
- **where from**: `man/pass.1:63-67`、`src/password-store.sh:321-366`（`.gpg-id` 書き `:348`、`reencrypt_path` 呼び `:364`）、`:110-140`。
- **決定性の壁**: gpg 暗号化の乱数セッション鍵で**記録拒否を予想**。gpg 決定化（例: 乱数 pin）が用意できる場合のみ実行可。

### P2: 鍵スコープをまたぐ `mv` の「移動済み・再暗号化前」窓
- **argv**: `pass mv -f teamA/site teamB/site`（fixture: `teamA/.gpg-id`=KEY-A、`teamB/.gpg-id`=KEY-B、git 無し）
- **why**: `mv` が先、`reencrypt_path` が後（`:629-630`）。間で切ると **teamB/ に KEY-A でしか読めないファイル**が置かれる。teamB のメンバーは読めず（可用性）、逆方向（制限の強いスコープへの移動）では**読めてはいけない鍵で読める状態が恒久化**（機密性）。rename は原子的でも操作全体は2段。
- **what property**: `pass.1:157-158`——「Passwords are selectively reencrypted to the corresponding keys of their new destination」。どのクラッシュ世界でも「元の場所に旧受信者のまま」か「新しい場所に新受信者で」のどちらかのみ。
- **where from**: `man/pass.1:157-158`、`src/password-store.sh:597-650`（`:629-630`, `:644`）。
- **決定性の壁**: 再暗号化ステップが非決定。**記録拒否を予想**（P1 と同じ条件付き）。

### P3: `rm` の複段削除（決定的に録れる唯一の足場）
- **argv**: `pass rm -f teamA/inner/site`（fixture: `teamA/inner/` に対象1件、`teamA/` に別の生存ファイル、git 無し）
- **why**: `rm "$passfile"`（`:587`）→ `rmdir -p "${passfile%/*}"`（`:594`）の2段。窓自体は小さいが、gpg を一切呼ばないため**このターゲットで baseline が確実に録れる唯一の書き込み操作**であり、engine 疎通と checker の陽性対照を兼ねる。`rmdir -p` は空になった親を store の根に向かって連鎖削除するので、削除対象外の階層構造がどこまで残るかも固定できる。
- **what property**: `pass.1:147-151`——消えるのは指定した pass-name（とその空親ディレクトリ）だけ。どのクラッシュ世界でも兄弟エントリ・他ディレクトリは内容不変で存在。
- **where from**: `man/pass.1:147-151`、`src/password-store.sh:565-595`。
- **決定性**: 決定的と予想（rm/rmdir のみ）。
