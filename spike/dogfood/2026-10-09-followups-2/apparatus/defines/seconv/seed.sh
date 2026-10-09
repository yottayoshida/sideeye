set -eu
# 2026-10-09 user-data-4's seconv define; the binary is SeConv 5.2.0, the release #15829 was measured on.
# A two-cue SubRip file; --overwrite writes the shifted cues back over it.
rm -rf /s/seconv && mkdir -p /s/seconv
printf '1\r\n00:00:05,000 --> 00:00:07,000\r\nHello there, this is the first cue of a short file.\r\n\r\n2\r\n00:00:09,000 --> 00:00:11,000\r\nAnd this is the second one, which ends the file.\r\n\r\n' > /s/seconv/subs.srt
grep -q 'second one' /s/seconv/subs.srt
