#!/bin/sh
# Fails if todo list fails, or if it silently skipped an unreadable entry.
out=$(todo list 2>&1) || exit 1
printf '%s\n' "$out" | grep -q "Failed to read entry" && exit 1
exit 0
