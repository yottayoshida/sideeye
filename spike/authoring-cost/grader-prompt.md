# The grader's brief — what each of the two graders is handed, verbatim

Kept beside the rubric so that what a grader was asked is part of the record, not a thing the
operator typed differently each time. `TARGET` and the revision list are substituted; nothing
else changes between graders except the shuffled order of the revisions and their given ids.

---

あなたは採点者です。読むだけでよい。コマンドを実行しない・ファイルを編集しない。他の採点者の
答えは見えません。

対象リポ: REPO_PATH

次を読んでから採点してください:

1. 採点規則: `spike/authoring-cost/grade-rubric.md`（「Order of application」の段落と直後の注記、
   および「The four friction classes」を必ず読むこと）
2. 正解表（contract card）: `spike/authoring-cost/cards/TARGET.md`
3. 採点対象の define（与え ID → ファイル）。define の下に、その時点で被験者が
   **その define と同じディレクトリに置いていたファイル**がぶら下がります。記録された run では
   `check` / `setup` とそれらが呼ぶスクリプト、およびそれらが使うデータがこれにあたります。
   **入らないもの**: define が自分のディレクトリの外を名指ししたスクリプト、下位ディレクトリの
   中身、そして **Sideeye 自身の report**（この rubric が「ツールが何を報告するかで採点しない」と
   言っているため、意図的に外しています）。ぶら下がりが無い revision は「スクリプトが無かった」
   ではなく「この仕組みが動く前に記録された run」の可能性があります:
   GIVEN_IDS

**与え ID の順序に意味はありません。** どれが後に書かれたかは伝えていません。良し悪しを順番から
推測せず、card だけを基準に採点してください。**ファイル名も、その中の連番も手がかりにしないで
ください**——define の下にぶら下がるスクリプトのファイル名は観測順の通し番号を持っていますが、
それは採点対象の並び順とは別物で、そこから順序を読み取ろうとすると誤ります。

rubric の「Output form」に従って、1 行 1 define:

```
<与え ID>  <verdict>  <friction classes or none>  <the card line it turns on, or ->
```

そのあとに 1 行ずつ、rubric が言う散文（この対象の作者が知っていなければならなかったことを 1 文で）
を付けてください。report は 2000 字以内。

---

## Why the ids are shuffled per grader

The two graders receive the same revisions under different ids, in different orders. A verdict
that tracks the id rather than the content shows up as the two sheets disagreeing in a way the
mapping explains — which is a reading about the graders, and the study publishes it rather than
resolving it.
