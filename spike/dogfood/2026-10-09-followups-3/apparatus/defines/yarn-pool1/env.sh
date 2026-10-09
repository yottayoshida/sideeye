# libuv runs Node's asynchronous file calls on its thread pool, four threads by default; with one,
# they share one thread, and the threads wall (multiple_threads_detected) is not met (transcripts/lab-1.txt).
export UV_THREADPOOL_SIZE=1
