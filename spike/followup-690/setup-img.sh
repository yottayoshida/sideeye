#!/bin/sh
# mogrify's setup, as spike/followup-527's setup-img.sh: three PNGs made by ffmpeg. Run by
# Sideeye as --setup, so the inputs' times are the setup's, as they were in that run.
mkdir -p "$SIDEEYE_STATE_DIR"
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y "$SIDEEYE_STATE_DIR/img$n.png"
done
