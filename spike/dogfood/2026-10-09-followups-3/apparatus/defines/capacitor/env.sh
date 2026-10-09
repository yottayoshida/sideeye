# The Capacitor CLI requires Node 22; the box's Node 22 is /opt/node22 (Dockerfile, tenth layer).
export PATH=/opt/node22/bin:$PATH

# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one
# they share a thread, and the threads wall is not met (yarn and trash-cli, transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
