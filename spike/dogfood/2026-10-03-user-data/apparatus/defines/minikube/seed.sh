set -eu
rm -rf /s/minikube && mkdir -p /s/minikube/.minikube/config
printf '{\n    "cpus": 4,\n    "driver": "docker",\n    "memory": 4096\n}\n' > /s/minikube/.minikube/config/config.json
