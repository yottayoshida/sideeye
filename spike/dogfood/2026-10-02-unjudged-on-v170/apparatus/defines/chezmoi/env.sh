# 2026-09-27-supervised-static/apparatus/run.sh line 32: chezmoi's own database (its state about
# what it last wrote) lives under $HOME, so $HOME is the define's. Sourced after /ap/env.sh, so
# this overrides the box-wide HOME; sideeye.toml's `apparatus` entry checks it reached the engine.
HOME=/s/chezmoi/home; export HOME
