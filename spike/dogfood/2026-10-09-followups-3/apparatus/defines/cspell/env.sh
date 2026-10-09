# cspell refuses trixie's Node 20 (">=22.18.0 is required"); the box's Node 22 is /opt/node22.
export PATH=/opt/node22/bin:$PATH

# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one
# they share a thread, and the threads wall is not met (yarn and trash-cli, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
