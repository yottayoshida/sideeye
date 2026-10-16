#!/bin/sh
find "$SIDEEYE_STATE_DIR" -mindepth 1 -delete
echo seed > "$SIDEEYE_STATE_DIR/seed"
