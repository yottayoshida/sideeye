git init -q demo && cd demo
printf 'DB_PASSWORD=hunter2\n' > .env; printf 'PROD=x\n' > .env.production
printf '.env.keys\n.env.production\n' > .gitignore
dotenvx encrypt -f .env && git add -A && git commit -qm init
strace -f -qq -o /dev/null -e inject=renameat,renameat2:signal=KILL dotenvx encrypt -f .env.production
git add -A && git status --short
