# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one they
# share a thread and the threads wall is not met (2026-10-09 follow-ups 3, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
export XDG_CONFIG_HOME=/s/xdg
# removeIgnore() unsets dotenvx.protect.ignoreFile in git's global config after it rewrites the ignore
# file, and refuses to run without it. Outside the state that config is not restored between worlds,
# so every world after the first took the refusal (UNKNOWN kill_did_not_land, the first attempt); here
# it lives under the state, restored with it, and is scratch.
export GIT_CONFIG_GLOBAL=/s/xdg/git/config
