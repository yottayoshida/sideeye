#!/bin/sh
# The neovim issues the novelty search surfaced whose titles name a shada error (E576, E138), shada
# corruption or lost shada state, read in full — body and every comment — for whether any of them
# names this run's mechanism: the target removed before the rename (vim_rename's os_remove), a kill
# or crash between the two, or the temporary left behind. Prints each issue's state, its size, and
# every line that mentions rename, unlink, a temporary, crash, kill, power or atomic. The first version
# printed at most 8 such lines per issue and so did not read #8587 or #6875 in full (the second
# review of this record); #11955, cited from #8587, is added.
set -u
for n in 6875 11876 11955 29186 10461 8587 23345 3469 3736 4108 4169 6652 8064; do
  gh api repos/neovim/neovim/issues/$n --jq '"== neovim/neovim#\(.number) [\(.state)] \(.created_at[:10]) \(.comments) comment(s): \(.title)"'
  { gh api repos/neovim/neovim/issues/$n --jq '.body // ""'; gh api --paginate "repos/neovim/neovim/issues/$n/comments?per_page=100" --jq '.[].body'; } \
    | tr '\r' '\n' > /tmp/issue.txt
  echo "   $(wc -l < /tmp/issue.txt) lines of body and comments; lines naming rename, unlink, remove, a temporary, crash, kill, power or atomic: $(grep -c -i -E 'rename|unlink|os_remove|remov|tmp\.|\.tmp|temporar|crash|kill|power|atomic|interrupt' /tmp/issue.txt)"
  grep -i -n -E 'rename|unlink|os_remove|tmp\.|\.tmp|temporar|crash|kill|power|atomic' /tmp/issue.txt | cut -c1-220 | sed 's/^/   /'
done
