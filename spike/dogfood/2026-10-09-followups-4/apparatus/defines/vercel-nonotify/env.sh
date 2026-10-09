
# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one
# they share a thread, and the threads wall is not met (yarn and trash-cli, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1

# Round 2: vercel reads the update-notifier convention, NO_UPDATE_NOTIFIER, and then starts no version
# check (dist/index.js: SHOULD_CHECK_FOR_UPDATES). Whether that removes the second thread's mkdir is measured.
export NO_UPDATE_NOTIFIER=1
