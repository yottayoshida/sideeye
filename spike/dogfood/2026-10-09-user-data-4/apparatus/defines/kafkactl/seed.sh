set -eu
# Two contexts in config.yml and the current one in current-context.yml (written by kafkactl itself);
# `config use-context b` rewrites current-context.yml (lab 18: O_TRUNC, write, fsync).
rm -rf /s/aux/home/.config/kafkactl /s/kc-in && mkdir -p /s/aux/home/.config/kafkactl /s/kc-in
printf 'contexts:\n  a:\n    brokers:\n      - localhost:9092\n  b:\n    brokers:\n      - localhost:9093\n' > /s/aux/home/.config/kafkactl/config.yml
kafkactl config use-context a > /s/kc-seed.log 2>&1
grep -q 'current-context: a' /s/aux/home/.config/kafkactl/current-context.yml
