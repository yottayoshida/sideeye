#!/bin/sh
# Paperless's own sanity checker over the library the crash left: every document's original,
# archived version and thumbnail is where its row says, with the checksum the row stores. Its exit
# status is 0 whatever it finds, so its lines are read. An ERROR (a document whose file is not where
# its row says, or whose checksum differs) rejects; a global warning alone does not — an orphaned file
# in the media directory, such as the `__paperless_write_test_<pid>__` probe a killed run leaves, is
# not a document lost (the first pass rejected on it, transcripts/explore-s4b.txt's first paperless run).
. /ap/defines/paperless/env.sh
cd /opt/paperless-ngx/src
out=$(/opt/paperless-venv/bin/python manage.py document_sanity_checker --no-progress-bar 2>&1)
printf '%s\n' "$out" | grep -E 'ERROR  |Orphaned|No issues|Found [0-9]' | sed 's/^/checker(paperless): /'
printf '%s\n' "$out" | grep -q -E 'ERROR  |document\(s\) with errors' && exit 1
printf '%s\n' "$out" | grep -q -E 'No issues detected|global warning'
