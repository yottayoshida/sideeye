#!/bin/sh
# What each candidate's mutating command is, as the installed tool describes it — read before any
# define is written, so the operation comes from the tool's own help and not from memory.
#
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1005 sh /ap/probe-help.sh
#
# Each probe gets 15 s and no stdin; a tool that waits for a terminal shows as a timeout here.
. /ap/env.sh
h() { n=$1; shift; echo "=== $n: $*"; timeout -k 2 15 "$@" </dev/null 2>&1 | head -${LINES_MAX:-40}; echo "--- rc $?"; }
h geth geth account update --help
h geth-ver geth version
h monero monero-wallet-cli --help
h steamguard steamguard --help
h steamguard-enc steamguard encrypt --help
h lighthouse lighthouse account validator modify --help
h lighthouse-vm lighthouse validator-manager --help
h jump jump --help
h gcm git-credential-manager --help
h firewalld firewall-offline-cmd --help
h i18n-tasks i18n-tasks add-missing --help
h dwpage php /opt/dokuwiki/bin/dwpage.php --help
h basic-memory basic-memory tool --help
h basic-memory-edit basic-memory tool edit-note --help
h ffsubsync ffsubsync --help
h rio rio edit-info --help
h kaggle kaggle config --help
h kaggle-set kaggle config set --help
h hf hf auth --help
h hf-logout hf auth logout --help
h skopeo skopeo logout --help
h oras oras logout --help
h regctl regctl registry set --help
h nerdctl nerdctl logout --help
h velero velero client config set --help
h codex codex mcp add --help
h sheldon sheldon add --help
h micro micro -help
h ytdlp yt-dlp --version
h vercel vercel telemetry --help
h wrangler wrangler telemetry --help
h gemini gemini mcp add --help
h serverless serverless config credentials --help
h ntfslabel ntfslabel --help
h wandb wandb offline --help
h posh oh-my-posh config migrate --help
h opam opam option --help
h stack stack config set --help
h juliaup juliaup config --help
h goi18n goi18n merge -help
h toybox toybox sed --help
h gltfpack gltfpack
h solvespace solvespace-cli --help
h gltf-transform gltf-transform --help
