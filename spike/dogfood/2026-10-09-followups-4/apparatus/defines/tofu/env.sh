
# One P for the Go scheduler, to see whether the threads wall moves the way it does for Node with one
# libuv thread. A blocking call still hands its P to another thread, so this may not be enough.
export GOMAXPROCS=1
