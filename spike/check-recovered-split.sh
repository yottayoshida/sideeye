#!/bin/sh
# The recovery checker paired with recover-split.sh (#606): both files hold a whole old or new
# version.
set -u
s=${SIDEEYE_STATE_DIR:?}
for f in derived primary; do
    case "$(cat "$s/$f.txt" 2>/dev/null)" in
        "$f-old"|"$f-new") ;;
        *) echo "$f.txt holds neither the old nor the new content" >&2; exit 1 ;;
    esac
done
exit 0
