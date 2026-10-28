#!/bin/sh
# After a crash anywhere in `gqlgen generate`, the resolver code the developer wrote is still in
# schema.resolvers.go, and running the same generate again (the documented way back) succeeds and
# leaves a project that builds.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(gqlgen): $*"; exit 1; }
. /ap/defines/gqlgen/env.sh
f="$d/schema.resolvers.go"
[ -f "$f" ] || fail "schema.resolvers.go is missing"
for want in 'Written by the developer: store the todo' 'Written by the developer: every todo, newest first.'; do
    grep -q -F "$want" "$f" || fail "the developer's resolver body is gone from schema.resolvers.go ($want)"
done
( cd /s/gql && gqlgen generate ) > /tmp/gql-rerun.txt 2>&1 || fail "re-running gqlgen generate exited $?: $(tail -c 300 /tmp/gql-rerun.txt)"
grep -q -F 'Written by the developer: store the todo' "$f" || fail "after the re-run the developer's resolver body is gone"
( cd /s/gql && go build ./... ) > /tmp/gql-build.txt 2>&1 || fail "the project does not build after the re-run: $(tail -c 300 /tmp/gql-build.txt)"
exit 0
