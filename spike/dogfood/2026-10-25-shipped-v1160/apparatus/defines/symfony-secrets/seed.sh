set -eu
# A Symfony 8.1 skeleton (made in the box at build) with a prod vault holding three secrets, its cache
# warmed so the operation does not build it. The vault is made here, under the same pinned getrandom.
rm -rf /s/sf && mkdir -p /s && cp -a /opt/symfony-app /s/sf && cd /s/sf
php bin/console secrets:generate-keys --env=prod > /dev/null 2>&1
printf 'postgresql://app:Pg-2026-prod@db.internal:5432/app' | php bin/console secrets:set DATABASE_URL - --env=prod > /dev/null 2>&1
printf 'example-stripe-live-secret-0001' | php bin/console secrets:set STRIPE_SECRET - --env=prod > /dev/null 2>&1
printf 'smtp://mailer:Mx-2026@smtp.internal:587' | php bin/console secrets:set MAILER_DSN - --env=prod > /dev/null 2>&1
php bin/console cache:warmup --env=prod > /dev/null 2>&1
install -m 755 /ap/defines/symfony-secrets/check.sh /s/sf-check.sh
