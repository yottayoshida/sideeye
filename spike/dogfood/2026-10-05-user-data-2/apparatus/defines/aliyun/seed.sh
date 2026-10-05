set -eu
rm -rf /s/aux/home/.aliyun /s/aliyun-in && mkdir -p /s/aliyun-in
aliyun configure set --profile work --mode AK --access-key-id FAKE-ALI-ID-00001 --access-key-secret examplesecret0001 --region cn-hangzhou > /s/aliyun-in/seed.log 2>&1
aliyun configure set --profile home --mode AK --access-key-id FAKE-ALI-ID-00002 --access-key-secret examplesecret0002 --region ap-northeast-1 >> /s/aliyun-in/seed.log 2>&1
test -s /s/aux/home/.aliyun/config.json
