#!/bin/sh
# The first review of this record: probe-checkers.sh tried three states per checker (setup, operation
# done, file emptied), and the emptied file is the accident, not a test of each predicate. Here each
# checker explore.sh ran for aws-cli, hatch, jbang and pyenv meets a state that breaks one predicate
# and nothing else, starting from the completed operation's state. Checkers and setups are
# materialised by explore.sh itself. No Sideeye.
set -u
ONLY=" none " sh /hostap/explore.sh > /dev/null 2>&1
AP=/localrun/ap
export HOME=/localrun/aux/home TMPDIR=/localrun/aux/tmp JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR"
fresh() {  # fresh <name> <setup> <op...>: the completed operation's state in $SD
  SD=/localrun/pp/$1; export SD; mkdir -p "$SD"; "$AP/$2" > /dev/null 2>&1; shift 2
  ( set -f; eval "$(printf '%s' "$*" | sed "s|@SD@|$SD|g")" ) > /dev/null 2>&1
}
ck() {  # ck <checker> <label> <expected rc>
  "$AP/$1" > /tmp/c.txt 2>&1; printf '  %-58s rc=%s (expected %s) %s\n' "$2" "$?" "$3" "$(head -1 /tmp/c.txt | cut -c1-110)"
}
AWS_OP='env AWS_CONFIG_FILE=@SD@/config AWS_SHARED_CREDENTIALS_FILE=@SD@/credentials aws configure set aws_secret_access_key fake-secret-rotated-for-probe-only-0000 --profile work'
echo "== check-aws.sh"
fresh aws setup-aws.sh "$AWS_OP"; ck check-aws.sh "the completed operation" 0
fresh aws1 setup-aws.sh "$AWS_OP"; sed -i 's/^aws_access_key_id = FAKE-ID-WORK-0000001$/aws_access_key_id = FAKE-ID-WORK-9999999/' $SD/credentials; ck check-aws.sh "work profile's access key changed" 1
fresh aws2 setup-aws.sh "$AWS_OP"; sed -i 's/^aws_secret_access_key = fake-secret-rotated-for-probe-only-0000$/aws_secret_access_key = neither-old-nor-new/' $SD/credentials; ck check-aws.sh "work profile's secret neither old nor new" 1
fresh aws3 setup-aws.sh "$AWS_OP"; sed -i 's/^aws_access_key_id = FAKE-ID-DEFAULT-0001$/aws_access_key_id = FAKE-ID-DEFAULT-9999/' $SD/credentials; ck check-aws.sh "default profile's access key changed" 1
fresh aws4 setup-aws.sh "$AWS_OP"; sed -i 's/^aws_secret_access_key = fake-secret-default-for-probe-only-000000$/aws_secret_access_key = changed/' $SD/credentials; ck check-aws.sh "default profile's secret changed (not a predicate)" "0: not checked"
echo "== check-hatch.sh"
HATCH_OP='env HATCH_CONFIG=@SD@/config.toml hatch config set terminal.styles.info italic'
fresh h0 setup-hatch.sh "$HATCH_OP"; ck check-hatch.sh "the completed operation" 0
fresh h1 setup-hatch.sh "$HATCH_OP"; sed -i 's/^info = "italic"$/info = "underline"/' $SD/config.toml; ck check-hatch.sh "terminal.styles.info neither bold nor italic" 1
fresh h2 setup-hatch.sh "$HATCH_OP"; printf 'mode = "local"\n[dirs\n' >> $SD/config.toml; ck check-hatch.sh "config.toml does not parse" 1
fresh h3 setup-hatch.sh "$HATCH_OP"; sed -i '/^mode = /d' $SD/config.toml; ck check-hatch.sh "the top-level mode key removed" 1
echo "== check-jbang.sh"
JB_OP='env JBANG_DIR=@SD@ java -jar /opt/jbang-0.141.0/bin/jbang.jar config set second.key second-value'
fresh j0 setup-jbang-java.sh "$JB_OP"; ck check-jbang.sh "the completed operation" 0
fresh j1 setup-jbang-java.sh "$JB_OP"; sed -i 's/^first.key=first-value$/first.key=other-value/' $SD/jbang.properties; ck check-jbang.sh "first.key holds another value" 1
echo "== check-pyenv.sh"
PY_OP='env PYENV_ROOT=@SD@ pyenv global 3.12.4'
fresh p0 setup-pyenv.sh "$PY_OP"; ck check-pyenv.sh "the completed operation" 0
fresh p1 setup-pyenv.sh "$PY_OP"; printf '3.9.1\n' > $SD/version; ck check-pyenv.sh "version names a version that is not installed" 1
fresh p2 setup-pyenv.sh "$PY_OP"; rm -f $SD/version; ck check-pyenv.sh "version removed" 1
