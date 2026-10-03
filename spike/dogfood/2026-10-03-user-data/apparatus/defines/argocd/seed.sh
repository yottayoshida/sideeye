set -eu
rm -rf /s/argocd /s/aux/home/.config/argocd && mkdir -p /s/argocd /s/aux/home/.config/argocd
printf 'contexts:\n- name: home\n  server: argocd.home.example.invalid\n  user: home\n- name: work\n  server: argocd.work.example.invalid\n  user: work\ncurrent-context: home\nservers:\n- grpc-web-root-path: ""\n  server: argocd.home.example.invalid\n- grpc-web-root-path: ""\n  server: argocd.work.example.invalid\nusers:\n- auth-token: placeholder-home-credential\n  name: home\n- auth-token: placeholder-work-credential\n  name: work\n' > /s/argocd/config
chmod 600 /s/argocd/config
