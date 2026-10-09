Title: A checker that refuses the state the define starts from is reported as the target's FAIL, at crash point 1

Sideeye falsifies a checker before an exploration — it must fail on a corrupted state — but nothing asks it to accept the state the define starts from. A checker that refuses that state fails in the world killed before the first operation, and the report reads as the target's FAIL: `earliest crash point 1 of N`, `after (start)()`, `the checker exited non-zero after restart`. Nothing the target did is in that world; the defect is the define's.

Met on the 2026-10-09 follow-ups 2 dogfood run on v1.10.0 (`spike/dogfood/2026-10-09-followups-2/`). xmake's first checker accepted only `theme = "plain"` (the value the operation writes), while the seed's `xmake.conf` holds `theme = "default"`:

```
world 1: theme is 'default'
world 2: xmake.conf does not end its table (0 bytes)
FAIL  2 of 4 explored worlds violated an invariant
earliest    crash point 1 of 3
            after  (start)()
            before open(/s/xm/.xmake/xmake.conf)
checker     falsified before the run (corrupted state -> check failed); ran in 4 world(s)
```

(`transcripts/explore/xmake/explore.txt`). World 2 is a real FAIL; world 1 is the checker refusing the untouched state, and the verdict line counts both against the target. With the checker fixed to accept the seeded value, the same define FAILs 1/4 (`transcripts/explore/xmake-fixed/explore.txt`).

The world before the first operation holds exactly the restored initial state, so a define whose checker refuses it cannot be judging the operation. Directions, not measured: run the checker on the initial state beside the falsification and refuse the define when it fails there (as the falsification refuses `checker_not_falsified`); or report a crash point 1 violation as the define's, not the target's.

Filed-under: wrong-verdict — a FAIL is reported against the target for a state the target never touched.
