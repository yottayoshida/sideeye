#!/bin/sh
# The Nextcloud and Symfony windows reproduced without Sideeye, for the reports: strace runs the
# operation and sends SIGKILL as the process enters the one syscall the report names (strace's
# signal injection lands on entry, so that call never runs). No pinning: the reports
# need the state a kill leaves, not two runs that match byte for byte.
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro sideeye-sv1025-s2 sh /ap/repro-s2-php.sh
set -u
export FAKETIME= ; : > /etc/ld.so.preload

echo "=== Nextcloud: occ config:system:set, killed entering the write(config.php) after its ftruncate"
rm -rf /s/ncconf && mkdir -p /s && cp -a /opt/nc-config-proto /s/ncconf
export NEXTCLOUD_CONFIG_DIR=/s/ncconf/
echo "before: $(wc -c < /s/ncconf/config.php) bytes"
strace -f -qq -P /s/ncconf/config.php -e trace=write -e inject=write:signal=KILL:when=1 \
    php /opt/nextcloud/occ config:system:set trusted_domains 1 --value=cloud.example.com > /tmp/nc.out 2>&1
echo "exit: $?"
echo "after:  $(wc -c < /s/ncconf/config.php) bytes"
php /opt/nextcloud/occ status 2>&1 | head -3
echo "--- the same command run through, for comparison"
rm -rf /s/ncconf && cp -a /opt/nc-config-proto /s/ncconf
php /opt/nextcloud/occ config:system:set trusted_domains 1 --value=cloud.example.com > /dev/null 2>&1
echo "run through: $(wc -c < /s/ncconf/config.php) bytes"

echo
echo "=== Symfony: secrets:generate-keys --rotate, killed entering the second open of DATABASE_URL's file (the one that seals it again), both new keys written"
rm -rf /s/sf && cp -a /opt/symfony-app /s/sf && cd /s/sf
php bin/console secrets:generate-keys --env=prod > /dev/null 2>&1
printf 'postgresql://app:pw@db:5432/app' | php bin/console secrets:set DATABASE_URL - --env=prod > /dev/null 2>&1
printf 'example-secret-0001' | php bin/console secrets:set STRIPE_SECRET - --env=prod > /dev/null 2>&1
php bin/console cache:warmup --env=prod > /dev/null 2>&1
ls -l config/secrets/prod/; echo "before:"; php bin/console secrets:list --reveal --env=prod 2>&1 | grep -E "DATABASE_URL|STRIPE_SECRET"
f=$(ls config/secrets/prod/prod.DATABASE_URL.*.php)
strace -f -qq -P "$f" -e trace=openat -e inject=openat:signal=KILL:when=2 \
    php bin/console secrets:generate-keys --rotate --env=prod > /tmp/sf.out 2>&1
echo "exit: $?"
echo "after:"; php bin/console secrets:list --reveal --env=prod 2>&1 | grep -E "DATABASE_URL|STRIPE_SECRET|ERROR|rror" | head -4
ls -l config/secrets/prod/
