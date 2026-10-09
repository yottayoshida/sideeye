# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one they
# share a thread and the threads wall is not met (2026-10-09 follow-ups 3, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
# protect writes git's global config and attributes file under HOME (env.sh puts HOME at /s/aux/home).
