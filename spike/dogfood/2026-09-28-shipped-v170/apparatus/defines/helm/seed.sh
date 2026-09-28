set -eu
rm -rf /s/helm && mkdir -p /s/helm/cfg /s/helm/cache
cat > /s/helm/cfg/repositories.yaml <<'Y'
apiVersion: ""
generated: "0001-01-01T00:00:00Z"
repositories:
- name: a
  url: https://a.example.invalid/charts
- name: b
  url: https://b.example.invalid/charts
Y
printf 'apiVersion: v1\nentries: {}\n' > /s/helm/cache/b-index.yaml
printf 'b\n' > /s/helm/cache/b-charts.txt
