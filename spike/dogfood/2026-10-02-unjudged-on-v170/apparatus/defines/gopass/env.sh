# 2026-09-27-supervised-static/apparatus/run.sh lines 43 and 49: the age passphrase gopass reads
# instead of asking (a test value from that run, not a real secret), and the home directory whose
# store is the judged root. sideeye.toml's `apparatus` entries check both reached the engine.
GOPASS_AGE_PASSWORD=testpassphrase; export GOPASS_AGE_PASSWORD
GOPASS_HOMEDIR=/s/gopass/gp; export GOPASS_HOMEDIR
