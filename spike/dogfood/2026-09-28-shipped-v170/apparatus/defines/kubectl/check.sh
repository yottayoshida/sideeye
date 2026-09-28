#!/bin/sh
# kubectl must still read the kubeconfig: both contexts present, the current one a or b
# (switched or not), and the user's entry intact.
f=/s/kubectl/config
cur=$(kubectl config view --kubeconfig "$f" -o 'jsonpath={.current-context}' 2>&1) || { echo "kubectl cannot read the kubeconfig: $cur" >&2; exit 1; }
case "$cur" in a|b) : ;; *) echo "current-context is '$cur', neither a nor b" >&2; exit 1 ;; esac
n=$(kubectl config get-contexts --kubeconfig "$f" -o name 2>/dev/null | wc -l)
[ "$n" -eq 2 ] || { echo "the kubeconfig holds $n contexts, not 2" >&2; exit 1; }
u=$(kubectl config view --kubeconfig "$f" --raw -o 'jsonpath={.users[0].name}' 2>/dev/null)
[ "$u" = u ] || { echo "the user entry is gone (got '$u')" >&2; exit 1; }
