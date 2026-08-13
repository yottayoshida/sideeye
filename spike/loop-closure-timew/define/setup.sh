#!/bin/sh
# The define's setup: seed one committed interval the day before the operation's.
# Copied verbatim from the heredoc in spike/dogfood-timew-replay.sh — promoted to a
# committed file because the loop-closure experiment hands the define to the agent
# (the declared invariant is part of the counterexample, DESIGN §17).
set -eu
timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null
