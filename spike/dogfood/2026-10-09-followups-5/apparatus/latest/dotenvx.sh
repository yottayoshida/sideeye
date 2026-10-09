# dotenvx/dotenvx#1012, the report's steps.
mkdir -p /work/dx && cd /work/dx
printf 'DB_PASSWORD=hunter2\n' > .env
strace -f -qq -P "$PWD/.env" -e trace=write,pwrite64 -e inject=write,pwrite64:signal=KILL dotenvx encrypt -f .env; echo "exit $?"
ls -la | awk '{print $5, $NF}'
cat .env
