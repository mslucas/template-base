#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_FILE="${ROOT_DIR}/infra/k8s/manifests/web-entrypoints.yaml"

add_literal() {
  local key="$1"
  local src="$2"
  echo "  ${key}: |" >> "${OUT_FILE}"
  sed 's/^/    /' "${src}" >> "${OUT_FILE}"
}

cat > "${OUT_FILE}" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-static
  namespace: __K8S_NAMESPACE__
data:
YAML

add_literal "index.html" "${ROOT_DIR}/src/frontend/webapp/index.html"
add_literal "main.js" "${ROOT_DIR}/src/frontend/webapp/main.js"
add_literal "design-system-components.js" "${ROOT_DIR}/src/frontend/design-system/components.js"
add_literal "design-system-tokens.css" "${ROOT_DIR}/src/frontend/design-system/tokens.css"
add_literal "shared-platform-client.js" "${ROOT_DIR}/src/frontend/shared/platform-client.js"
add_literal "shared-runtime-config.js" "${ROOT_DIR}/src/frontend/shared/runtime-config.js"
add_literal "shared-auth-client.js" "${ROOT_DIR}/src/frontend/shared/auth-client.js"

cat >> "${OUT_FILE}" <<'YAML'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-placeholder
  namespace: __K8S_NAMESPACE__
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: webapp-placeholder
  template:
    metadata:
      labels:
        app.kubernetes.io/name: webapp-placeholder
    spec:
      containers:
        - name: nginx
          image: nginx:1.27.5-alpine
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: static-site
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: static-site
          configMap:
            name: webapp-static
            items:
              - key: index.html
                path: index.html
              - key: main.js
                path: main.js
              - key: design-system-components.js
                path: design-system/components.js
              - key: design-system-tokens.css
                path: design-system/tokens.css
              - key: shared-platform-client.js
                path: shared/platform-client.js
              - key: shared-runtime-config.js
                path: shared/runtime-config.js
              - key: shared-auth-client.js
                path: shared/auth-client.js
---
apiVersion: v1
kind: Service
metadata:
  name: webapp-placeholder
  namespace: __K8S_NAMESPACE__
spec:
  selector:
    app.kubernetes.io/name: webapp-placeholder
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: admin-static
  namespace: __K8S_NAMESPACE__
data:
YAML

add_literal "index.html" "${ROOT_DIR}/src/frontend/admin/index.html"
add_literal "main.js" "${ROOT_DIR}/src/frontend/admin/main.js"
add_literal "design-system-components.js" "${ROOT_DIR}/src/frontend/design-system/components.js"
add_literal "design-system-tokens.css" "${ROOT_DIR}/src/frontend/design-system/tokens.css"
add_literal "shared-platform-client.js" "${ROOT_DIR}/src/frontend/shared/platform-client.js"
add_literal "shared-runtime-config.js" "${ROOT_DIR}/src/frontend/shared/runtime-config.js"
add_literal "shared-auth-client.js" "${ROOT_DIR}/src/frontend/shared/auth-client.js"

cat >> "${OUT_FILE}" <<'YAML'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-placeholder
  namespace: __K8S_NAMESPACE__
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: admin-placeholder
  template:
    metadata:
      labels:
        app.kubernetes.io/name: admin-placeholder
    spec:
      containers:
        - name: nginx
          image: nginx:1.27.5-alpine
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: static-site
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: static-site
          configMap:
            name: admin-static
            items:
              - key: index.html
                path: index.html
              - key: main.js
                path: main.js
              - key: design-system-components.js
                path: design-system/components.js
              - key: design-system-tokens.css
                path: design-system/tokens.css
              - key: shared-platform-client.js
                path: shared/platform-client.js
              - key: shared-runtime-config.js
                path: shared/runtime-config.js
              - key: shared-auth-client.js
                path: shared/auth-client.js
---
apiVersion: v1
kind: Service
metadata:
  name: admin-placeholder
  namespace: __K8S_NAMESPACE__
spec:
  selector:
    app.kubernetes.io/name: admin-placeholder
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-entrypoint
  namespace: __K8S_NAMESPACE__
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - __HOST_APP__
      secretName: __HOST_APP__-tls
  rules:
    - host: __HOST_APP__
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: webapp-placeholder
                port:
                  number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: admin-entrypoint
  namespace: __K8S_NAMESPACE__
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - __HOST_ADMIN__
      secretName: __HOST_ADMIN__-tls
  rules:
    - host: __HOST_ADMIN__
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-placeholder
                port:
                  number: 80
YAML

echo "Rendered ${OUT_FILE}"

