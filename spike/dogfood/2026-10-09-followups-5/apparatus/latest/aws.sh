# aws/aws-cli#10648, the report's steps.
mkdir -p /work/aws && cd /work/aws
export AWS_CONFIG_FILE=$PWD/config AWS_SHARED_CREDENTIALS_FILE=$PWD/credentials
printf '[default]\nregion = us-east-1\n' > config
printf '[default]\naws_access_key_id = EXAMPLE-ID-1\naws_secret_access_key = example-secret-1\n\n[work]\naws_access_key_id = EXAMPLE-ID-2\naws_secret_access_key = example-secret-2\n' > credentials
wc -c credentials
(ulimit -f 0; /opt/bin/aws configure set aws_secret_access_key example-secret-3 --profile work); echo "exit $?"
wc -c credentials
