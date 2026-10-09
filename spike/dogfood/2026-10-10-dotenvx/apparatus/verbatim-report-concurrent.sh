mkdir -p demo/apps/a demo/apps/b && cd demo
printf 'A_SECRET=a\n' > apps/a/.env; printf 'B_SECRET=b\n' > apps/b/.env
dotenvx encrypt -fk .env.keys -f apps/a/.env & dotenvx encrypt -fk .env.keys -f apps/b/.env & wait
dotenvx get A_SECRET -fk .env.keys -f apps/a/.env; dotenvx get B_SECRET -fk .env.keys -f apps/b/.env
