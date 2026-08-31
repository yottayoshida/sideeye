#!/bin/sh
# Create the container a timed run measures on, and print what was created.
#
#   image=$(docker build -q -f spike/onboarding-clock/Dockerfile -t sideeye-onboarding .)
#   sh spike/onboarding-clock/box.sh "$image"
#
# PROTOCOL.md's "The fresh machine" says a run uses a container built by the
# Dockerfile beside it, and "What one run proves" says re-runs use a fresh box.
# Until #383 nothing enforced either: the operator typed `docker run` by hand and
# `run-clock.sh` asked only whether *a* box was running and network-off. Run 2's
# `docker run` failed with a name conflict, the launcher proceeded against a
# container started 2h51m earlier, and what caught it was a human reading the
# error in a terminal. A box that had already been used — a rehearsal that ran
# sideeye against the target — is exactly what the rehearsal boundary exists to
# prevent, and nothing in the apparatus would have said a word.
#
# So the launcher owns the box. There is no pre-existing one to inherit, which
# closes staleness and rehearsal contamination with the same move: a container
# that did not exist a second ago cannot have been used.
#
# This lives in its own file because `run-clock.sh` cannot be executed by any
# test — it refuses to start inside a Claude session, and past that it needs the
# `claude` CLI, an authenticated account, and a box. None of that is needed to
# create a container, so the enforcement is testable only if it is separable.
# That is the residue #383 named: a change to the launcher ships on review alone.
set -eu

IMAGE=${1:?usage: box.sh <image-ref, e.g. the sha256: id docker build -q printed>}

# The production spelling is the default and is never passed by the launcher.
# `clock-audit.py`'s box predicate hard-codes `docker exec onboarding-box`, and
# so do prompt.md and the launcher's allow-set, so parameterising the name for
# real would let the audit disagree with the launcher in silence. This override
# exists so a test can drive the lifecycle without touching a real run's box —
# and CI uses it, because a teardown written against the real name is a
# `docker rm -f onboarding-box` that deletes a shipped run's evidence the first
# time someone runs it on a self-hosted runner or pastes it into a terminal.
# `spike/check-box-name.sh` holds the production spelling across every file.
BOX_NAME=${BOX_NAME:-onboarding-box}

# Any state, not just running. An exited container still holds the name, and it
# is still a box this run did not create. (This is also why the run below does
# not pass `--rm`: with it, an exited box removes itself and this refusal covers
# nothing. The other reason is that the evidence should survive a daemon
# restart, which stops every container.)
existing=$(docker inspect -f '{{.Id}} {{.State.Status}} {{.Created}}' "$BOX_NAME" 2>/dev/null || true)
if [ -n "$existing" ]; then
    echo "refusing to launch: a container named $BOX_NAME already exists." >&2
    echo "  $existing" >&2
    echo "This run would inherit it. PROTOCOL.md says a re-run uses a fresh box," >&2
    echo "and a box that was already used is what the rehearsal boundary forbids." >&2
    echo "" >&2
    echo "If it holds a completed run's evidence, keep its contents first — the" >&2
    echo "image it was built from is not reachable by tag once the box is gone:" >&2
    echo "  docker commit $BOX_NAME sideeye-onboarding-<run>-asbuilt:<date>" >&2
    echo "Then remove it and launch again:" >&2
    echo "  docker rm -f $BOX_NAME" >&2
    exit 1
fi

# `docker run -d` prints the new container's id on stdout. This script's stdout
# is a key=value record its caller captures, so that line is dropped here rather
# than left to be filtered downstream, where a parser would skip it in silence.
docker run -d --network=none --name "$BOX_NAME" "$IMAGE" >/dev/null

# Read back rather than assume. The two checks the launcher used to make live
# here now, and they are still worth making: they used to ask about a box
# somebody else created, and now they ask whether the one just created came up
# the way the protocol requires (an image whose CMD exits would pass `docker
# run` and fail here).
running=$(docker inspect -f '{{.State.Running}}' "$BOX_NAME")
[ "$running" = "true" ] || {
    echo "$BOX_NAME was created but is not running (State.Running=$running)" >&2
    exit 1
}
netmode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$BOX_NAME")
[ "$netmode" = "none" ] || {
    echo "$BOX_NAME is not network-off; the protocol requires --network=none" >&2
    exit 1
}

# The record. `meta.json` carries this so the claim "this run measured a fresh
# box" is checkable from the run's own evidence — before #383 it was checkable
# only from whoever's terminal the launch happened in, which is how run 2's
# deviation was found and is not a method.
docker inspect -f 'container_id={{.Id}}
image_id={{.Image}}
created={{.Created}}' "$BOX_NAME"
