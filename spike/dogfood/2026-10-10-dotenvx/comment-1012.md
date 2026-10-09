Not posted (2026-10-10): picked against in the value reading — see RESULTS.md, "Reported upstream".

Measured 2.34.2 beside 2.32.4 with Sideeye: `encrypt` (one file, two files, and a second file while `.env.keys` holds the first one's key), `set`, `decrypt` and `del` now keep the old or the new content at every kill point. The second-file case was the worst on 2.32.4: `.env.keys` emptied, and the encrypted `.env` left without its key. Two things remain, in #A and #B.
