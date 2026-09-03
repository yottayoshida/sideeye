#!/bin/sh
# The define's setup: seed one committed interval the day before the operation's.
# The one canonical text (#65): the scripts that stage or replay the define copy it
# from here. The loop-closure experiment hands it to the agent as part of the
# counterexample (the declared invariant, DESIGN §17).
set -eu
timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null
