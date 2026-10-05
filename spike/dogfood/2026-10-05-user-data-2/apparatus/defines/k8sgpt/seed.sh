set -eu
rm -rf /s/aux/home/.config/k8sgpt /s/k8sgpt-in && mkdir -p /s/k8sgpt-in
k8sgpt auth add --backend openai --model gpt-4o --password sk-test-aaaa > /s/k8sgpt-in/seed.log 2>&1
k8sgpt auth add --backend localai --model llama --baseurl http://localhost:8080/v1 >> /s/k8sgpt-in/seed.log 2>&1
test -s /s/aux/home/.config/k8sgpt/k8sgpt.yaml
