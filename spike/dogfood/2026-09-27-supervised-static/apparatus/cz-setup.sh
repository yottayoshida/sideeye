#!/bin/sh
# chezmoi keeps its own state (a bolt database) under $HOME; clear it so every world applies
# into an empty destination from the same starting point. The judged root is the destination.
rm -rf "$HOME/.config/chezmoi" "$HOME/.local/share/chezmoi" "$HOME/.cache/chezmoi"
