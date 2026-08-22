# stow 2.3.1 — scout proposals

## 1. 永続状態の所在
- **target ツリーそのもの**（symlink 群と実ディレクトリ）が状態。`-t <target>` で明示指定。stow dir（`-d <dir>`、パッケージ実体）は通常読み取り専用だが、**`--adopt` のときだけ書かれる**。DB やメタファイルは持たない——「Stow doesn't store an extra state between runs」（`lib/Stow.pm.in:41-43` POD）。エンジンの state dir は「target と stow dir を含む1ツリー」にするのが自然（例: `<state>/target/` と `<state>/stow/`）。

## 2. 状態を書くコマンド
- `stow <pkg>`（-S）、`stow -D <pkg>`、`stow -R <pkg>`、混在指定 `stow -D old -S new`。
- 実行は二相: plan（conflict 検出のみ）→ `process_tasks` が **task 列を順に実行**（`lib/Stow.pm.in:1462-1481`）。task は mkdir / symlink / unlink / rmdir / move の素朴列（`process_task`, `:1493-1536`）。journal も途中再開も無い＝**タスク列のあらゆる境界がクラッシュ窓**。
- **本質的にマルチファイル**: 1パッケージで数十 task。特に:
  - **tree unfolding**（`:487-508`）: 既存の folded symlink を `do_unlink` → `do_mkdir` → **既存パッケージ側の link を張り直し** → 新パッケージの link 追加、の順で置換。
  - `--adopt`（`:537-539`）: target の実ファイルを `do_mv` で **stow dir へ移動**してから link。move は cross-fs だと copy+delete に落ちる実装（`:1525-1529` のコメント）。

## 3. ドキュメントの約束
- `doc/stow.texi:762-775`（Deferred Operation）: conflict があれば「terminates **without making any modifications** to the filesystem」、これにより「much less risk of a package being **partially stowed or unstowed**」。さらに 2.0 以前の欠点として「leaving the target tree in an **inconsistent state**」を明示——**「部分 stow」がこのツール自身の定義する故障状態**。
- `doc/stow.texi:683-687`（Ownership）: 「**Stow will never delete anything that it doesn't own.**」「Anything Stow owns, **it can recompute if lost**」→ そのままクラッシュ checker の2本柱（非所有物の保存則＋所有物の再計算可能性）。
- `doc/stow.texi:199-201`: 「Stow will never delete any files, directories, or links that appear in a Stow directory … so **it's always possible to rebuild the target tree**.」→ 回復契約（re-run で収束すること）。
- `doc/stow.texi:779-798`（Mixing Operations）: `stow -D emacs-21.3 -S emacs-21.4a` の1回起動を推奨し「the amount of time in which GNU Emacs is unavailable is **minimised**」。
- `--adopt`（`:372-390`）: 「the file becomes adopted by the stow package, **without its contents changing**」。

## 4. fsck / verify / undo
- **`chkstow` が同梱**（`bin/chkstow.in`）: `--badlinks`（既定モード、`:60-64`）が dangling symlink を「Bogus link」として報告（`:103`）、`--aliens` が非 symlink を報告。**ready-made checker**。修復は「もう一度 stow/-R を実行」が上記 rebuild 契約の実体。

## 5. 決定性
- **決定的と予想**。書くのは symlink / dir / rename だけで、内容バイトに時刻・乱数を含まない。symlink の指し先は相対パスで固定。task 順もツリー走査順で固定。baseline 記録は通る見込み。（唯一の注意: `--adopt` で cross-fs 時のみ copy+delete になるが、単一 state dir 内なら rename。）

## 提案（ランク順）

### P1: tree unfolding を誘発する2パッケージ目の stow
- **argv**: `stow -d <state>/stow -t <state>/target pkgB`（fixture: pkgA が stow 済みで `target/share` が folded symlink → `stow/pkgA/share`。pkgB も `share/` 配下にファイルを持つ）
- **why**: unfold は「folded link を unlink → 実 dir を mkdir → **pkgA の link を全部張り直す** → pkgB の link を張る」の多段列（`lib/Stow.pm.in:494-508` → `process_tasks :1474-1478`）。unlink〜再 link の間で切ると、**今回の操作で名指ししていない pkgA のファイル群が target から到達不能**になる。「1パッケージの追加が既設パッケージを壊す」形で、被害が操作スコープの外に出る。
- **what property**: `stow.texi:683-687` の Ownership 契約のクラッシュ拡張——(a) Stow が所有しない target 内エントリは全世界で不変、(b) 所有物は「re-run（`stow pkgA pkgB` 再実行）が conflict なしに完走して全 link が復元される」（`:199-201` の rebuild 契約）、(c) `chkstow --badlinks` が Bogus link を報告しない。
- **where from**: `doc/stow.texi:683-687`・`:199-201`・`:762-775`、`lib/Stow.pm.in:487-508`・`1462-1481`、`bin/chkstow.in:60-64,103`。

### P2: `-D old -S new` の1回起動 restow
- **argv**: `stow -d <state>/stow -t <state>/target -D pkgA-1.0 -S pkgA-2.0`（fixture: pkgA-1.0 stow 済み、2.0 は一部ファイルが増減）
- **why**: task 列は unstow 系（unlink/rmdir）の後に stow 系（mkdir/symlink）が並ぶ。中間で切ると**パッケージが丸ごと不在**（doc が「unavailable 時間の最小化」を売りにしている、その unavailable 状態が凍結される）か、新旧 link の混在。texi 自身が「partially stowed or unstowed」を 2.0 で潰したはずの故障状態として名指ししている。
- **what property**: `stow.texi:779-798` の単一起動 restow 契約＋`:762-775`——どのクラッシュ世界でも「1.0 が完全」「2.0 が完全」「不在だが re-run で 2.0 が conflict なしに完成し、stow dir は無傷（`:199-201`）」のいずれかに落ちること。dangling link（chkstow の Bogus link）はどの世界でも不可。
- **where from**: `doc/stow.texi:762-775`・`779-798`・`199-201`、`lib/Stow.pm.in:1462-1481`、`bin/chkstow.in:103`。

### P3: `--adopt` のファイル移動窓
- **argv**: `stow -d <state>/stow -t <state>/target --adopt pkgA`（fixture: `target/etc/app.conf` が**実ファイル**として存在し、pkgA も同相対パスを持つ）
- **why**: `do_mv(target→package)` の後に `do_link`（`lib/Stow.pm.in:537-539`）。間で切ると、ユーザーの実ファイルが**元の場所から消えて** stow dir の中にだけある（target 側から見れば消失）。また move は実装コメント通り cross-fs で copy+delete に落ちる（`:1525-1529`）——その場合は**内容の torn copy** まであり得る。adopt は「Stow が非所有物に書く」唯一の経路で、never-delete 契約の適用限界を突く。
- **what property**: `stow.texi:384-385`「the file becomes adopted … **without its contents changing**」——どのクラッシュ世界でも、当該ファイルの**バイト列は target か package のどちらかに完全な形で存在**し、かつ最終的に（re-run で）target パスから到達可能に戻せること。
- **where from**: `doc/stow.texi:372-390`、`lib/Stow.pm.in:537-539`・`1523-1531`。
