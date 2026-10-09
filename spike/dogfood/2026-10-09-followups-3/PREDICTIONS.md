# Predictions — 2026-10-09 follow-ups 3

Written before each run.

| target | run | prediction | why |
|---|---|---|---|
| yarn 4.18.1 `config set`, `UV_THREADPOOL_SIZE=1` | the page's path | **FAIL** | past the threads wall (lab 1), `.yarnrc.yml` is rewritten in place (2026-10-09 user-data-4, lab 8) |
| trash-cli 7.2.0 `trash`, `UV_THREADPOOL_SIZE=1` | the page's path | **PASS** | the file is renamed into the trash; the info file is new |

## The rest, before they run

yarn FAILed and trash-cli PASSed as predicted (`transcripts/pool1.txt`). The same variable now goes to
the fifteen other Node targets the threads wall refused, and `GOMAXPROCS=1` to four Go ones; the five
targets that cleared a gate in an earlier campaign and were never explored run as their defines stand.
How each writes was not read, so PASS/FAIL is a guess; the prediction with more weight is the first
column.

| target | past the threads wall? | guess |
|---|---|---|
| bibtex-tidy, dotenvx, gemini-cli, gltf-transform, lingui, vercel, cspell, capacitor, eslint, prettier, stylelint, svgo, npm `pkg set`, joplin, Bitwarden CLI (`UV_THREADPOOL_SIZE=1`) | **yes**, most; a few may meet a child process or a second wall | FAIL for most: Node's `fs.writeFile` truncates before it writes |
| tofu, doctl, infracost, plakar (`GOMAXPROCS=1`) | **no**: a blocking call hands its P to another thread, so writes still come from more than one | — |
| dokuwiki (page save) | — | FAIL (its tracker's #677: pages saved empty on a full disk) |
| lighthouse (validator definitions) | — | PASS (its #2338 writes through a temporary) |
| jump (scores) | — | FAIL (its #9: scores.json malformed on a full disk) |
| keyring with keyrings.alt's plaintext file | — | FAIL |
| git-lfs `install` | **no**: every write is a `git config` child (`child_touched_state_dir`) | — |
