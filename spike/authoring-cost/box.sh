#!/bin/sh
# Create the container one authoring run happens in, and print what was created.
#
#   image=$(docker build -q -f spike/authoring-cost/Dockerfile --build-arg TARGET=<pkg> .)
#   sh spike/authoring-cost/box.sh "$image"
#
# The launcher owns the box, for the reason spike/onboarding-clock/box.sh records from #383: a
# pre-existing container can be one a rehearsal already used, and nothing in the apparatus would
# say so. A container that did not exist a second ago cannot have been used.
#
# It lives in its own file because run-authoring.sh cannot be executed by any test — it needs the
# `claude` CLI, an authenticated account and a box — while creating a container needs none of
# that. Enforcement that cannot be exercised ships on review alone.
set -eu

IMAGE=${1:?usage: box.sh <image-ref, e.g. the id docker build -q printed>}

# The production spelling is the default and is never passed by the launcher: prompt.md names it
# in the shell form the subject must use, and spike/authoring-cost/check-box-name.sh holds every
# copy of the name to this one. The override exists so a test can drive the lifecycle without
# touching a real run's box — a teardown written against the production name is a `docker rm -f`
# that deletes a published run's evidence the first time someone pastes it into a terminal.
BOX_NAME=${BOX_NAME:-authoring-box}

if docker ps -a --format '{{.Names}}' | grep -qx "$BOX_NAME"; then
    echo "box.sh: a container named $BOX_NAME already exists (any state). A run measures a" >&2
    echo "        fresh machine, so this refuses rather than inheriting it. Remove it first." >&2
    exit 1
fi

# --network=none: the build had the network, the run must not. The subject's own model traffic
# does not pass through here (PROTOCOL.md, "One leg only"), which is why this is not called
# isolation.
id=$(docker run -d --name "$BOX_NAME" --network=none "$IMAGE")
echo "box: $BOX_NAME"
echo "id: $id"
echo "image: $IMAGE"
docker exec "$BOX_NAME" sh -c 'ls /home/user/authoring' | sed 's/^/contents: /'
