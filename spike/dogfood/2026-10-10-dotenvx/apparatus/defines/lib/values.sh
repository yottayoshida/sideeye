# Sourced by every check.sh here. Each helper prints what it found when it does not hold, and sets bad=1;
# the checker exits with $bad after its last line.
bad=0
expect() { # <file> <KEY> <value>... ; '<absent>' accepts a missing key (MISSING_KEY), nothing else
  f=$1; k=$2; shift 2
  got=$(dotenvx get "$k" -f "$f" 2>/tmp/dx.err); rc=$?
  for w in "$@"; do
    [ "$w" = '<absent>' ] && [ $rc -ne 0 ] && grep -q MISSING_KEY /tmp/dx.err && return 0
    [ $rc -eq 0 ] && [ "$got" = "$w" ] && return 0
  done
  echo "$f $k: dotenvx get reads '$(printf %s "$got" | cut -c1-40)' (exit $rc) $(head -1 /tmp/dx.err | cut -c1-90)"; bad=1
}
contains() { # <file> <line>: the line is still in the file
  grep -qxF -- "$2" "$1" 2>/dev/null && return 0
  echo "$1: no line '$2' ($(wc -c < "$1" 2>/dev/null || echo missing) bytes)"; bad=1
}
nonempty_with() { # <file> <word>
  grep -q -- "$2" "$1" 2>/dev/null && return 0
  echo "$1: no '$2' ($(wc -c < "$1" 2>/dev/null || echo missing) bytes)"; bad=1
}
no_private_key_staged() { # nothing `git add -A` would take holds a DOTENV_PRIVATE_KEY line
  for f in $(git -C "$SIDEEYE_STATE_DIR" ls-files --others --exclude-standard); do
    grep -q '^DOTENV_PRIVATE_KEY' "$SIDEEYE_STATE_DIR/$f" 2>/dev/null && { echo "git would stage $f, which holds a private key"; bad=1; }
  done
  return 0
}
recoverable() { # <file> <KEY> <value>: the value reads back through dotenvx as it stands, or some private
  # key held anywhere in the state (.env.keys, the stand-in keyring, the stand-in 1Password or Bitwarden) decrypts it
  got=$(dotenvx get "$2" -f "$1" 2>/tmp/dx.err) && [ "$got" = "$3" ] && return 0
  for k in $(cat "$SIDEEYE_STATE_DIR"/.env.keys "$SIDEEYE_STATE_DIR"/keyring.json "$SIDEEYE_STATE_DIR"/op.json "$SIDEEYE_STATE_DIR"/bw.json 2>/dev/null | grep -o '[0-9a-f]\{64\}'); do
    [ "$(DOTENV_PRIVATE_KEY=$k dotenvx get "$2" -f "$1" 2>/dev/null)" = "$3" ] && return 0
  done
  echo "$1 $2: no key anywhere in the state decrypts it; dotenvx get reads '$(printf %s "$got" | cut -c1-30)' $(head -1 /tmp/dx.err | cut -c1-80)"; bad=1
}
