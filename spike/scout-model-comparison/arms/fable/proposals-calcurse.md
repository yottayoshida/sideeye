# calcurse 4.7.1 — scout proposals

## 1. 永続状態の所在
- data dir（`-D <dir>` で明示指定可）: `apts`（予定・イベント）、`todo`、`notes/`（ノート本文。**ファイル名＝内容の SHA1**）。conf dir: `conf`、`keys`、`hooks/`。既定は `$XDG_DATA_HOME/calcurse` 等、`-D` が両方を兼ねる（`doc/manual.txt:860-905` の「calcurse files」節に全レイアウト）。
- 読み書き両方するのは `apts` / `todo` / `notes/`。import 時のログは `get_tempdir()`（/tmp 側）に出るので状態ディレクトリ外（`src/io.c:1396-1397`）。

## 2. 状態を書くコマンド（非対話）
- **すべての保存が「本体ファイルへの fopen(path, "w") 直接 truncate 書き」**。temp file も rename も fsync も無い: `io_save_apts` `src/io.c:277`、`io_save_todo` `src/io.c:326`。
- `-i <ics>`（import）: `io_import_data` → **notes/ へのノート生成**（`generate_note`, `src/note.c:59-75`、これも fopen "w" 直書き）→ `io_save_apts` → `io_save_todo`（`src/args.c:966-969`）。**1操作で3種のファイル群を順に書く**、このターゲット最太のクロスファイル窓。
- `-F`（filter 書き戻し）/ `-P --filter-invert ...`（purge）: 読み込み→ `io_save_todo` → `io_save_apts` の順で両ファイル書き戻し（`src/args.c:905-907`。`-F` の配線は `args.c:559-560`、`-P` は `581-583`、purge は `--filter-invert` 必須 `args.c:878`）。
- `-g`（gc）: notes/ の未参照ノートを削除。

## 3. ドキュメントの約束
- `doc/manual.txt`「calcurse files」節: 「the file name of each note file is a SHA1 hash of the note itself, multiple items can share the same note file」→ **notes/ の自己検証不変条件**（名前＝内容の SHA1）。
- 同節: `apts`「this file contains all of the events and user's appointments」→ apts の全件保存則。
- `doc/manual.txt:310`（`-F`）: 「Read items from the data files and write them back. … specifying a wrong filter might result it data loss!」→ 正しい（無変更）filter なら**何も失われない**ことが含意される契約。
- import 節: 「The icalendar DESCRIPTION property will be converted into calcurse format by adding a note to the item」→ item と notes/ の参照整合。

## 4. fsck / verify / undo
- 無し。唯一の修復系は `-g`（gc）で、これは**未参照ノートの掃除だけ**（manual.txt notes/ 節）。壊れた apts は読み込み時に `io_load_error` で fatal になるのみ。クラッシュ回復契約は実質ゼロ。

## 5. 決定性
- **決定的と予想**。apts/todo の行は日時・テキストのみで wall clock 刻印なし、ノート名は内容 SHA1（`src/note.c:65-66`）、並び順はロード時ソートで固定。import ログの乱数名 tempfile は /tmp 側で状態ディレクトリ外（`src/io.c:1396-1397`）。baseline 記録は通る見込み。`-i`/`-F` とも入力 fixture だけで出力が決まる。

## 提案（ランク順）

### P1: ical import の3段クロスファイル書き込み
- **argv**: `calcurse -D <state> -i <fixture>/import.ics`（fixture: 既存の予定・TODO・ノート付き item を持つ data dir ＋ DESCRIPTION 付き VEVENT/VTODO を含む ics）
- **why**: ノート生成（notes/ へ直書き）→ `apts` を fopen("w") で**その場 truncate**して全再書き→ `todo` も同様、の3段（`src/note.c:67`, `src/args.c:966-969`, `src/io.c:277,326`）。apts 書き込み中のどの境界で切っても**既存の全予定が短縮・消失した唯一のコピー**になる。2ファイル間で切れば世代混在。
- **what property**: 保存則——import 前から在った予定・イベント・TODO はどのクラッシュ世界でも全件残る（manual「apts contains all of the events and user's appointments」）。加えて notes/ 不変条件: 存在する全ノートは filename == SHA1(content)、apts/todo が参照するノートは必ず存在する。
- **where from**: `doc/manual.txt` calcurse files 節（apts/notes の引用は §上記）、`src/io.c:268-341`、`src/args.c:946-971`、`src/note.c:59-75`。

### P2: `-F` 無変更書き戻し＝「意図された変更ゼロ」の純粋クラッシュ試験
- **argv**: `calcurse -D <state> -F`（filter 指定なし→ type_mask=ALL `src/args.c:870-871`＝全件保持で両ファイル書き戻し）
- **why**: 意図された状態変化が**ゼロ**なのに `todo`→`apts` の順で両方を truncate 再書きする（`src/args.c:905-907`）。よってクラッシュ後に pre-state と1バイトでも意味差があれば全部シグナル。checker が最も単純になり、truncate-in-place の危険を最少ノイズで露出する。
- **what property**: `doc/manual.txt:310`「Read items from the data files and write them back」——書き戻しで item は増減しない。どのクラッシュ世界でもロード結果＝元の item 集合。
- **where from**: `doc/manual.txt:310`、`src/args.c:900-907`、`src/io.c:277,326`。

### P3: 共有ノートの in-place 上書き破壊（dedup 経路）
- **argv**: `calcurse -D <state> -i <fixture>/same-note.ics`（fixture: 既存 item が参照するノート X と**同一内容の DESCRIPTION** を持つ ics）
- **why**: `generate_note` は内容の SHA1 名で **既存ファイルがあっても無条件に fopen("w") で開き直して書く**（`src/note.c:67-71`）。同一内容→同一ファイル名なので、import が既存 item の共有ノートをその場 truncate→再書きする。途中で切ると**触っていないはずの既存 item のノートが破損**する（manual が明示する「multiple items can share the same note file」の共有構造が被害を widen する）。
- **what property**: 保存則＋notes/ 不変条件——import が名指ししていない既存 item のノート内容は不変、かつ全ノートで filename == SHA1(content)。
- **where from**: `src/note.c:59-75`、`doc/manual.txt` notes/ 節の共有・SHA1 命名の記述、import の DESCRIPTION→note 変換の記述（manual import 節）。
