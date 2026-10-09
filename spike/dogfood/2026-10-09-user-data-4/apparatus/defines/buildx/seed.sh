set -eu
# Two builder instances on the remote driver (no Docker daemon needed to record one); the operation
# appends a node to b1, which rewrites instances/b1 (lab 13: a .tmp- file created O_EXCL, fsync,
# rename). Each command stamps activity/<name> with the clock, so `activity` is scratch.
rm -rf /s/aux/home/.docker /s/bx && mkdir -p /s/bx
buildx create --name b1 --driver remote tcp://127.0.0.1:1234 > /s/bx-seed.log 2>&1
buildx create --name b2 --driver remote tcp://127.0.0.1:1235 >> /s/bx-seed.log 2>&1
[ -s /s/aux/home/.docker/buildx/instances/b1 ]
