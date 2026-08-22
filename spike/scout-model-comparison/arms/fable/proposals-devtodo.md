# devtodo 0.1.20 — scout proposals

## 1. 永続状態の所在
- カレントディレクトリの `.todo`（XML 1ファイル）が既定（`src/support.cc:23`）。`--database <file>` で明示指定可（`src/support.cc:229-230`、`doc/devtodo.1.in:78-79`）。グローバル DB は `~/.todo_global`（`support.cc:40`）。
- `--backup` 有効時は `.todo.1`〜`.todo.N` が回復用の追加状態（`doc/devtodo.1.in:126-127`）。
- `--link` を使うと**別ディレクトリの `.todo` が親 DB から参照される**＝状態が複数ファイルに広がる（`doc/devtodo.1.in:51-52`）。

## 2. 状態を書くコマンド
- `--add` / `--done` / `--not-done` / `--remove` / `--edit` / `--priority` / `--reparent` / `--purge` / `--link` — いずれも終了時に `TodoDB::save`。
- 保存の実体は **`ofstream of(file)` による本体 truncate 直書き**（`src/Loaders.cc:216`）。temp+rename 無し。
- `--backup N` 時は書く前に **`unlink`+`rename` の回転**を行い、最後に**生きている `.todo` を `.todo.1` へ rename してから新規に書く**（`src/TodoDB.cc:363-383`、rename は 381）。「旧本体が退避された直後・新本体ゼロバイト」の窓が構造的に存在する。
- **複数ファイル書き**: 親 DB の XML 書き出し中に `<link>` 要素へ到達すると **その場で子 DB の save を再帰呼び出し**（`src/Loaders.cc:172-181` / `src/TodoDB.cc:330-331`）。親が書きかけのまま子の書き込みが始まる＝親子両方が同時に torn になり得る。
- 空 DB は**ファイル unlink**（`src/TodoDB.cc:425-428`）。

## 3. ドキュメントの約束
- `doc/devtodo.1.in:18-19`「tdr <indices> — Remove the given items.」/ `:63-64`「Remove the note indexed by the given numbers, including any children.」→ 指定 item（とその子）**だけ**が消える。
- `doc/devtodo.1.in:126-127`（--backup）: 「Backup the database up to <n> times, **just before it is written to**. … To actually use one of these backups, you can either mv it to .todo or use --database .todo.<n>」→ **明文の回復契約**。
- `:138-139`（--purge）: 「Purge all completed items older than <days-old>. If <days-old> is omitted, all completed records are purged.」
- `:52`: link の削除は「does not remove the database itself, only the link」→ 子 DB の保存則。
- ロード側は壊れた XML を「no database loaders for database format or database corrupt」で fatal 拒否（`src/TodoDB.cc:315`）＝部分書きは**全 item アクセス不能**に増幅される。

## 4. fsck / verify / undo
- 検査・修復コマンドは無し。唯一の回復契約が `--backup`（既定 **0＝無効**、`src/support.cc:26`）。

## 5. 決定性
- **`--remove` / `--priority` / `--reparent` / `--purge`（日数省略形）は決定的と予想**: 新しい時刻を書かず、既存の `time=` 属性は fixture 由来で固定。`--purge` 引数省略は「完了済み全部」なので時計比較すら不要（`doc/devtodo.1.in:138-139`）。
- **`--add` / `--done` は記録拒否を予告**: `time(0)`（`src/support.cc:677`）を `time="…"` / `done="…"` 属性として XML に埋める（`src/Loaders.cc:177,191`）。時刻 pin があれば通る。
- 保存のたび stderr に `saving: <text>` のデバッグ出力が出る（`src/TodoDB.cc:322`）が状態バイトには無関係。

## 提案（ランク順）

### P1: `--backup 1 --remove` — 明文の回復契約を全境界で検査
- **argv**: `todo --database <state>/.todo --backup 1 --remove 2`（fixture: 3件以上・`time=` 属性は固定値）
- **why**: 保存列が「`.todo.1` の unlink → 生きている `.todo` を `.todo.1` へ rename（`TodoDB.cc:378-381`）→ 新 `.todo` を ofstream で頭から書く（`Loaders.cc:216`）」。rename と書き込み完了の間で切ると `.todo` が**不存在または書きかけ**になり、書きかけはロード時に corrupt 扱いで全 item 不可視（`TodoDB.cc:315`）。契約上その瞬間の命綱は `.todo.1`。
- **what property**: man の backup 契約（`devtodo.1.in:126-127`）——どのクラッシュ世界でも「`.todo` が旧 or 新の完全な DB」または「`.todo.1` が旧 DB として完全にロード可能」。かつ remove の約束（`:18-19`）——最終状態は「元の集合」か「元の集合−指定 item(とその子)」のみ。
- **where from**: `src/TodoDB.cc:363-383`、`src/Loaders.cc:213-240`、`doc/devtodo.1.in:18-19`・`126-127`。

### P2: 既定設定（backup 無し）の `--purge` — 素の truncate 書きでの保存則
- **argv**: `todo --database <state>/.todo --purge`（fixture: done/未 done 混在、`done=` 属性も固定値）
- **why**: backup 既定 0（`support.cc:26`）では保存＝本体 truncate 直書きのみ。書きかけで切れば done でない item まで全部道連れ（corrupt 拒否 `TodoDB.cc:315`）。purge は複数 item の同時削除なので diff が大きく、部分書き状態が最も出やすい。
- **what property**: `devtodo.1.in:138-139` の purge 約束——消えてよいのは completed のみ。どのクラッシュ世界でも未完了 item は全件・内容不変でロード可能。
- **where from**: `doc/devtodo.1.in:138-139`、`src/Loaders.cc:213-240`、`src/TodoDB.cc:315`、`src/support.cc:26`。

### P3: link された子 DB を巻き込む保存の入れ子書き込み
- **argv**: `todo --database <state>/.todo --priority 2 high`（fixture: item 1 が `--link` 済みの `<state>/sub/.todo` を指し、item 2 が通常 item。子 DB も dirty になるケースは probe で `--graft`/dotted index を追試）
- **why**: 親の XML を書いている**途中**で `<link>` に到達すると子 DB の save が同期実行される（`Loaders.cc:172-181`, `TodoDB.cc:330-331`）。子が dirty の場合は子も truncate 再書きされ、その間ずっと**親は書きかけのまま開いている**。子の書き込み中に切ると親・子の両 XML が同時に corrupt。
- **what property**: `devtodo.1.in:52`——link 操作は「does not remove the database itself」＝子 DB は親側の操作で失われない、の保存則をクラッシュ世界へ拡張したもの（親のみ変更する操作で子 DB が壊れてはならない）。
- **where from**: `src/Loaders.cc:172-181`、`src/TodoDB.cc:330-331`、`doc/devtodo.1.in:51-52`。
- **注**: 子を dirty にする正確な argv（dotted index の仕様）は静的読解では確定できなかった。probe 段階で要確認、という前提込みの P3。
