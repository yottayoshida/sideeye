Title: `nbqa black` leaves the notebook truncated when writing it back fails

If writing the reformatted notebook back fails or is interrupted, the notebook is left truncated and the original is gone:

```
$ wc -c < nb.ipynb
4271
$ ( ulimit -f 1; nbqa black nb.ipynb ); echo "exit $?"
reformatted nb.ipynb
...
nbQA failed to process nb.ipynb with exception "OSError(27, 'File too large')"
exit 123
$ wc -c < nb.ipynb
512
```

The 512 bytes left are not valid JSON.

#542 made this write go through a temporary file and a `move`. Since #573 the temporary `.py` is created next to the notebook (`mkstemp(dir=os.path.dirname(notebook))`, `nbqa/__main__.py` line 526), so in `nbqa/replace_source.py` line 295 `temp_notebook` is the notebook itself: line 209 opens it with `"w"`, and the `move` on line 297 renames it onto itself.

nbqa 1.9.1, black 26.5.1, Python 3.13; lines at `0d2662c`.

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), my personal crash-consistency checker: killed between the notebook's truncating open and its write, `nb.ipynb` was 0 bytes. Written with an AI assistant from its output, and checked by me.
</details>
