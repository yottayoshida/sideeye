set -eu
# A personal dictionary of a few words; the pipe adds two and saves (`*word`, then `#`), which
# hunspell appends (lab 10: O_WRONLY|O_CREAT|O_APPEND). hunspell reads its commands from stdin,
# which a define gives EOF, so the operation is `sh -c` with the input redirected from a file.
rm -rf /s/hun /s/hun-in && mkdir -p /s/hun /s/hun-in
printf 'zzyzx\nqwerty\nsideeye\n' > /s/hun/my.dic
printf '*flibbertigibbet\n*snorkack\n#\n' > /s/hun-in/words.txt
grep -q sideeye /s/hun/my.dic
