# Predictions — 2026-10-09 follow-ups 3

Written before each run.

| target | run | prediction | why |
|---|---|---|---|
| yarn 4.18.1 `config set`, `UV_THREADPOOL_SIZE=1` | the page's path | **FAIL** | past the threads wall (lab 1), `.yarnrc.yml` is rewritten in place (2026-10-09 user-data-4, lab 8) |
| trash-cli 7.2.0 `trash`, `UV_THREADPOOL_SIZE=1` | the page's path | **PASS** | the file is renamed into the trash; the info file is new |
