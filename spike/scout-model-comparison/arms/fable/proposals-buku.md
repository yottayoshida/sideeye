# buku 4.7 — scout proposals

## 1. 永続状態の所在
- 正本: SQLite DB 1ファイル `bookmarks.db`。既定は `$XDG_DATA_HOME/buku/`（無ければ `$HOME/.local/share/buku/`）配下（`buku:413-440` `get_default_dbdir`）。`--db <file>` で明示パス指定可（`buku:5518` で定義、`buku:5622` で `BukuDb(dbfile=...)` に配線）。
- 暗号化を使うと `bookmarks.db.enc` が同居する第2の状態ファイルになる（`buku:188`）。
- キャッシュ・scratch は無い。SQLite が作る `-journal` は書き込み中の一時随伴ファイル（クラッシュ窓の主役）。

## 2. 状態を書くコマンド
- `--add` / `--update` / `--delete` / `--import` / `--merge` / `--cleardb` — すべて同一 DB への SQL。
- **複数レコードをまたぐもの**:
  - `--delete N`: `DELETE`（`buku:1626-1627`）→ `compactdb`＝最終レコードの `DELETE`+`INSERT`（`buku:1463-1473`）を **1 commit** で行う（`buku:1630-1632`）。2行が同時に動く。
  - `--import`: 全レコードを `delay_commit=True` で入れて最後に 1 回 `conn.commit()`（`buku:2663-2669`）＝1トランザクション。
  - `--lock` / `--unlock`: **クロスファイル**。`.enc` を全書き→旧ファイルを `os.remove`（`buku:234-253` / decrypt 側 `buku:335-360`）。
- 注意: CLI の `--add` は `fetch=True` 既定でネットワークに出る（`buku:583`, CLI 呼び出し `buku:5690` は fetch を渡さない）。エンジン環境では `--update N --title 'X'`（`buku:893-894` で fetch 回避）か `--import` を使う。

## 3. ドキュメントの約束
- `buku.1:60`「When a record is deleted, the last record is moved to the index.」/ `buku.1:610`「The last index is moved to the deleted index to keep the DB compact.」→ **削除後、id は 1..N-1 の連続で、消えたのは指定した1件だけ・移動レコードの内容は不変**という checker がそのまま書ける。
- `README.md:70`「Portable, merge-able database」（弱いが、import/merge が既存レコードを壊さないという保存則の根拠）。
- `buku.1:85`: 暗号化の運用説明（unlock→使用→lock）。lock/unlock の途中断は運用フロー全体を壊す。
- 両ファイル併存はエラーで**起動拒否**: 「Both encrypted and flat DB files exist!」（`buku:198-201`, `buku:484-486`）。

## 4. fsck / verify / undo
- 無し。`--fixtags` は旧バージョンのタグ正規化専用（`buku.1:48`, `buku:2843`）で汎用検査ではない。クラッシュ回復契約は SQLite の journal 回復に全面依存（buku 自身は `PRAGMA` を一切設定しない: `buku:491-508`）。

## 5. 決定性
- **`--delete` / `--update --title` / `--import` は決定的と予想**（根拠: スキーマに timestamp・乱数列が無い `buku:501-507`、内容は argv／入力ファイル由来、`AUTOINCREMENT` 不使用）。baseline 記録は通る見込み。
- **`--add` は非推奨**: ネットワーク fetch の成否・エラー文言が環境依存（`buku:624-634`）。
- **`--lock`/`--unlock` は記録拒否を予告**: salt/IV に `os.urandom`（`buku:220`, `buku:225`）＋ `getpass` の対話入力（`buku:203-204`）。時刻でなく乱数なので faketime 系では消えない。urandom pin ＋ stdin 供給が無い限り測れない。

## 提案（ランク順）

### P1: 削除＋compact の2行トランザクション
- **argv**: `buku --nostdin --np --tacit --db <state>/bookmarks.db --delete 2`（fixture: 4件以上のブックマーク入り DB）
- **why**: 1 commit の中で「id=2 の DELETE」「id=max の DELETE」「id=max の内容を id=2 に INSERT」が走る（`buku:1626-1632` → `buku:1463-1475`）。SQLite の journal 書き込み・truncate・db 本体書き込みの各 I/O 境界で切ると、rollback 経路が正しくなければ「移動対象レコードの喪失（2件消える）」「id の穴」「重複」いずれかの torn 状態が出る。buku は journal_mode 等を設定せずデフォルト任せ（`buku:491-508`）。
- **what property**: `buku.1:60`/`buku.1:610` の約束——削除後の DB は「指定 1 件だけが消え、最終レコードが空いた index に内容不変で移り、id が連続」。クラッシュ世界では「旧状態そのまま or 新状態完成」の二値のみ許容。
- **where from**: `buku.1` 行60・610、`buku:1445-1477`（compactdb docstring 含む）、`buku:1626-1632`。

### P2: 一括 import の all-or-nothing と既存レコード保存
- **argv**: `buku --nostdin --np --tacit --db <state>/bookmarks.db --import <fixture>/new-bookmarks.md`（fixture: 既存 DB ＋ 20件程度の Markdown）
- **why**: 全 insert を溜めて最後に 1 回 commit（`buku:2663-2669`、`import_md` は `fetch=False` の7要素 tuple を返す `buku:3225`）。大きな1トランザクションはジャーナルが最も太る経路で、途中クラッシュ時に「既存レコードの破壊」「部分 import の残留」が出れば反例。
- **what property**: 保存則——クラッシュ世界でも import 前から在ったブックマークは全件・内容不変で読める。import は 0 件か全件（単一 commit 実装が意図する契約）。根拠: `README.md:70`「merge-able database」＋実装の単一 commit。
- **where from**: `buku:2663-2669`、`buku:3225`、`README.md:70`。

### P3: `--lock` のクロスファイル遷移（記録拒否前提の予告付き）
- **argv**: `buku --nostdin --np --db <state>/bookmarks.db --lock 8`（※パスワード2回の stdin 供給が必要）
- **why**: `.enc` 全書き→`os.remove(db)` の2ファイル遷移（`buku:234-253`）。完成した `.enc` と旧 `.db` が併存する瞬間があり、そこで止まると **buku は以後どのコマンドも起動拒否**（`buku:484-486`「Both encrypted and flat DB files exist!」）。回復コマンドは無く、ユーザーは手で片方を消すしかない＝クラッシュが恒久ロックアウトを作る。
- **what property**: lock 完了後は `{db, db.enc}` のちょうど一方だけが存在し、かつどのクラッシュ世界でもブックマーク全件が（復号すれば）回収可能。根拠: `buku.1:85` の運用契約と起動時検査 `buku:479-486`。
- **where from**: `buku:190-201`, `buku:234-258`, `buku:484-486`, `buku.1:85`。
- **決定性の予告**: `os.urandom`（`buku:220,225`）により **baseline 記録拒否を予想**。urandom の pin と stdin 供給をエンジンが持つ場合のみ実行可。持たないなら P3 は見送り。
