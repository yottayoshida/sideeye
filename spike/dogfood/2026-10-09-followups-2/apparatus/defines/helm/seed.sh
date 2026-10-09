set -eu
# 2026-10-02 gate-cleared-twelve's helm define; the binary is helm v4.3.0, as 2026-10-02 measured #32709.
rm -rf /s/helm && mkdir -p /s/helm/cfg /s/helm/cache
printf 'apiVersion: ""\ngenerated: "0001-01-01T00:00:00Z"\nrepositories:\n- name: a\n  url: https://a.example.invalid/charts\n- name: b\n  url: https://b.example.invalid/charts\n' > /s/helm/cfg/repositories.yaml
printf 'apiVersion: v1\nentries: {}\n' > /s/helm/cache/b-index.yaml
printf 'b\n' > /s/helm/cache/b-charts.txt
