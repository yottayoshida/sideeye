#!/bin/sh
# The neovim issues the novelty search surfaced whose titles name a shada error (E576, E138), shada
# corruption or lost shada state, read in full — body and every comment — for whether any of them
# names this run's mechanism: the target removed before the rename (vim_rename's os_remove), a kill
# or crash between the two, or the temporary left behind. Prints each issue's state and the lines
# that mention rename, unlink/remove, tmp, crash, kill, power or atomic.
set -u
for n in 6875 11876 29186 10461 8587 23345 3469 3736 4108 4169 6652 8064; do
  gh api repos/neovim/neovim/issues/$n --jq '"== neovim/neovim#\(.number) [\(.state)] \(.created_at[:10]) \(.comments) comment(s): \(.title)"'
  { gh api repos/neovim/neovim/issues/$n --jq '.body // ""'; gh api --paginate "repos/neovim/neovim/issues/$n/comments?per_page=100" --jq '.[].body'; } \
    | tr '\r' '\n' | grep -i -n -E 'rename|unlink|os_remove|remov|tmp\.|\.tmp|temporar|crash|kill|power|atomic|interrupt' | cut -c1-200 | head -8 | sed 's/^/   /'
done
