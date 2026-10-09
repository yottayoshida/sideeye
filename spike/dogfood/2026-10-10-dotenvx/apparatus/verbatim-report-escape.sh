printf '%s\n' 'PW=pa\$sword' > .env
dotenvx get PW
dotenvx encrypt > /dev/null && dotenvx get PW
dotenvx decrypt > /dev/null && grep ^PW .env && dotenvx get PW
