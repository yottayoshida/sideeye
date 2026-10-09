set -eu
. /ap/defines/keyring/env.sh
rm -rf /s/aux/data/python_keyring /s/keyring-in && mkdir -p /s/keyring-in
/opt/py/bin/python -I -c "import keyring; [keyring.set_password(s,u,p) for s,u,p in (('svc','u1','examplepass1'),('svc','u2','examplepass2'),('other','u3','examplepass3'))]"
test -s /s/aux/data/python_keyring/keyring_pass.cfg
