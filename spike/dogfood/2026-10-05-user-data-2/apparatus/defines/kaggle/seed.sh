set -eu
rm -rf /s/kg /s/kg-in && mkdir -p /s/kg /s/kg-in
printf '{"username":"alice","key":"0123456789abcdef0123456789abcdef"}\n' > /s/kg/kaggle.json && chmod 600 /s/kg/kaggle.json
