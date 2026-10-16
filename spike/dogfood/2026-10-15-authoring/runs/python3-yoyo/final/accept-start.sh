#!/bin/sh
# A state check.sh must accept: the valid start, as setup.sh leaves it.
set -eu
D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
