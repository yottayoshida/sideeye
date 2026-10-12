set -eu
# A Kubernetes manifest written by hand, comments and all, kept 0640 the way a repository's
# deploy files often are: yq -i is expected to carry the mode to what it writes.
rm -rf /s/yq && mkdir -p /s/yq
cat > /s/yq/deploy.yaml <<'EOF'
# Production web tier. Replicas are tuned by hand after each load test; see runbook 12.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: prod
  labels:
    app: web
    tier: frontend
spec:
  replicas: 2 # raised from 1 after the 2026-09 incident
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: registry.example.com/web:4.12.1
          ports:
            - containerPort: 8080
          env:
            - name: LOG_LEVEL
              value: info
            - name: FEATURE_FLAGS
              value: "checkout-v2,search-beta"
          resources:
            requests: { cpu: 250m, memory: 256Mi }
            limits: { cpu: "1", memory: 512Mi }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
            periodSeconds: 5
EOF
chmod 0640 /s/yq/deploy.yaml
