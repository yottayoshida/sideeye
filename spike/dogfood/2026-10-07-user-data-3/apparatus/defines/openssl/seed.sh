set -eu
rm -rf /s/ca /s/ca-in && mkdir -p /s/ca/newcerts /s/ca/private /s/ca-in && cd /s/ca
touch index.txt; echo 1000 > serial; echo 1000 > crlnumber
cat > ca.cnf <<'CNF'
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = /s/ca
database = $dir/index.txt
new_certs_dir = $dir/newcerts
certificate = $dir/ca.crt
private_key = $dir/private/ca.key
serial = $dir/serial
crlnumber = $dir/crlnumber
default_md = sha256
default_days = 365
default_crl_days = 30
policy = policy_any
unique_subject = no
[ policy_any ]
commonName = supplied
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = Test CA
CNF
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout private/ca.key -out ca.crt -days 365 -config ca.cnf > /s/ca-in/seed.log 2>&1
for n in a b c; do
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout $n.key -out $n.csr -subj /CN=$n >> /s/ca-in/seed.log 2>&1
  openssl ca -batch -config ca.cnf -in $n.csr -out $n.crt >> /s/ca-in/seed.log 2>&1
done
test "$(grep -c '^V' index.txt)" = 3
