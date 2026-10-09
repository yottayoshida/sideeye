set -eu
# Two Concourse targets in ~/.flyrc, written by hand (`fly login` reaches the network); the token is
# a placeholder. `edit-target` rewrites the file (lab 18: O_WRONLY|O_CREAT|O_TRUNC). The state is a
# directory holding .flyrc alone, through FLYRC... fly reads $HOME/.flyrc, so HOME's directory is the
# state root and env.sh points HOME at it.
rm -rf /s/flyhome /s/fly-in && mkdir -p /s/flyhome /s/fly-in
printf 'targets:\n  ci:\n    api: https://ci.example.org\n    team: main\n    token:\n      type: Bearer\n      value: placeholder-not-a-token\n  prod:\n    api: https://prod.example.org\n    team: ops\n' > /s/flyhome/.flyrc
grep -q prod /s/flyhome/.flyrc
