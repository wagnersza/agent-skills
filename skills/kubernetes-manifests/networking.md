# Networking

Production-ready patterns for Kubernetes networking resources.

## Service Types

### ClusterIP (Internal)

Default type for internal pod-to-pod communication.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-server
  labels: { app: api-server, component: backend }
spec:
  type: ClusterIP
  selector: { app: api-server }
  ports: [{ name: http, port: 80, targetPort: 8080, protocol: TCP }]
```

### Headless Service (StatefulSet)

Direct pod DNS — each pod gets `pod-0.postgres-headless.ns.svc.cluster.local`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
  labels: { app: postgres }
spec:
  type: ClusterIP
  clusterIP: None
  selector: { app: postgres }
  ports: [{ name: postgres, port: 5432, targetPort: 5432 }]
```

### NodePort and LoadBalancer

```yaml
# NodePort — exposes on each node's IP at a static port
apiVersion: v1
kind: Service
metadata:
  name: api-server-nodeport
spec:
  type: NodePort
  selector: { app: api-server }
  ports: [{ name: http, port: 80, targetPort: 8080, nodePort: 30080 }]
---
# LoadBalancer — provisions a cloud load balancer
apiVersion: v1
kind: Service
metadata:
  name: api-server-lb
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  type: LoadBalancer
  selector: { app: api-server }
  ports: [{ name: https, port: 443, targetPort: 8080 }]
```

## Ingress

NGINX ingress with TLS termination, path-based routing, and cert-manager.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myplatform-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit-rps: "50"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.example.com, app.example.com]
      secretName: myplatform-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: api-server, port: { number: 80 } } }
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend, port: { number: 80 } } }
```

## NetworkPolicy

### Default Deny All

Start with deny-all in every namespace, then add explicit allows.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: myapp-ns
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

### Application Traffic Rules

Frontend to backend ingress, backend to database egress.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-server-policy
  namespace: myapp-ns
spec:
  podSelector: { matchLabels: { app: api-server } }
  policyTypes: [Ingress, Egress]
  ingress:
    - from: [{ podSelector: { matchLabels: { app: frontend } } }]
      ports: [{ protocol: TCP, port: 8080 }]
  egress:
    - to: [{ podSelector: { matchLabels: { app: postgres } } }]
      ports: [{ protocol: TCP, port: 5432 }]
```

### Cross-Namespace Monitoring

Allow Prometheus in the monitoring namespace to scrape pods.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: myapp-ns
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } }
          podSelector: { matchLabels: { app: prometheus } }
      ports: [{ protocol: TCP, port: 9090 }]
```

### DNS and External HTTPS Egress

DNS targets kube-system CoreDNS specifically. External HTTPS excludes private ranges.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-and-https-egress
  namespace: myapp-ns
spec:
  podSelector: { matchLabels: { app: api-server } }
  policyTypes: [Egress]
  egress:
    - to:  # DNS to CoreDNS only
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }
          podSelector: { matchLabels: { k8s-app: kube-dns } }
      ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
    - to:  # External HTTPS only
        - ipBlock: { cidr: 0.0.0.0/0, except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16] }
      ports: [{ protocol: TCP, port: 443 }]
```

## DNS Patterns

Kubernetes DNS follows predictable naming conventions:

```
# Same namespace — service name only
api-server

# Cross-namespace — full FQDN
api-server.backend-ns.svc.cluster.local

# StatefulSet pod — pod ordinal in headless service
postgres-0.postgres-headless.database-ns.svc.cluster.local
```

## EndpointSlice

Modern alternative to Endpoints for routing to external services.

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-database
  labels: { kubernetes.io/service-name: external-database }
addressType: IPv4
ports: [{ name: postgres, port: 5432, protocol: TCP }]
endpoints:
  - addresses: ["10.200.1.50"]
    conditions: { ready: true }
---
apiVersion: v1
kind: Service
metadata:
  name: external-database
spec:
  ports: [{ name: postgres, port: 5432, targetPort: 5432 }]
```

## Best Practices

1. **Start with default-deny** NetworkPolicies in every namespace, then add explicit allows.
2. **Use least-privilege network rules** — allow only the specific ports and pod selectors needed.
3. **Prefer ClusterIP** for internal services; use LoadBalancer or Ingress only for external access.
4. **Use DNS names over IPs** — `service.namespace.svc.cluster.local` instead of hardcoded pod IPs.
5. **Terminate TLS at the Ingress** — use cert-manager for automated certificate management.
6. **Configure health checks** on Ingress backends to route traffic only to healthy pods.
7. **Apply rate limiting** at the Ingress layer to protect backend services from traffic spikes.
8. **Expose metrics endpoints** — annotate services for Prometheus scraping with standard ports.
