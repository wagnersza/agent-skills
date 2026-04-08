# Service Mesh

Production-ready patterns for Istio and Linkerd service mesh configurations.

## Istio Installation

Profiles: `minimal` (core only), `default` (production), `demo` (all features).

```bash
istioctl install --set profile=default -y
kubectl label namespace default istio-injection=enabled
```

## VirtualService

### Header-Based Routing

Route traffic to different backends based on request headers.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-routing
spec:
  hosts: [api.example.com]
  gateways: [api-gateway]
  http:
    - match:
        - headers:
            x-api-version: { exact: v2 }
      route:
        - destination: { host: api-v2, port: { number: 80 } }
    - route:
        - destination: { host: api-v1, port: { number: 80 } }
```

### Weighted Traffic Split (Canary)

Gradually shift traffic between service versions.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-canary
spec:
  hosts: [api-server]
  http:
    - route:
        - destination: { host: api-server, subset: stable }
          weight: 90
        - destination: { host: api-server, subset: canary }
          weight: 10
      timeout: 10s
      retries: { attempts: 3, perTryTimeout: 3s, retryOn: 5xx,reset }
```

## DestinationRule

Connection pool settings, outlier detection, and load balancing for a service.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-server
spec:
  host: api-server
  trafficPolicy:
    connectionPool:
      tcp: { maxConnections: 100 }
      http: { h2UpgradePolicy: DEFAULT, http1MaxPendingRequests: 100, http2MaxRequests: 1000 }
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
    loadBalancer:
      simple: LEAST_REQUEST
  subsets:
    - name: stable
      labels: { version: v1 }
    - name: canary
      labels: { version: v2 }
```

## Gateway

Ingress gateway with HTTPS termination and HTTP-to-HTTPS redirect.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: api-gateway
spec:
  selector: { istio: ingressgateway }
  servers:
    - port: { number: 443, name: https, protocol: HTTPS }
      tls:
        mode: SIMPLE
        credentialName: api-tls-cert
      hosts: [api.example.com]
    - port: { number: 80, name: http, protocol: HTTP }
      tls: { httpsRedirect: true }
      hosts: [api.example.com]
```

## mTLS — PeerAuthentication

Start `PERMISSIVE` during migration, then switch to `STRICT`.

### Namespace-Wide

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

### Mesh-Wide

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

## Traffic Mirroring

Mirror a percentage of live traffic to a shadow service for validation.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-mirror
spec:
  hosts: [api-server]
  http:
    - route:
        - destination: { host: api-server, subset: stable }
      mirror:
        host: api-server
        subset: canary
      mirrorPercentage:
        value: 10.0
```

## Circuit Breakers

Limit connections and eject unhealthy hosts. Typically configured via `DestinationRule` (see the connection pool and outlier detection fields in the DestinationRule section above).

## Fault Injection

Inject controlled delays and aborts for resilience testing.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-fault-test
spec:
  hosts: [api-server]
  http:
    - fault:
        delay:
          percentage: { value: 10 }
          fixedDelay: 5s
        abort:
          percentage: { value: 5 }
          httpStatus: 503
      route:
        - destination: { host: api-server }
```

## AuthorizationPolicy

Zero-trust access control restricting traffic by service account and HTTP method.

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-authz
  namespace: production
spec:
  selector:
    matchLabels: { app: api-server }
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/frontend"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/v1/*"]
    - from:
        - source:
            principals: ["cluster.local/ns/monitoring/sa/prometheus"]
      to:
        - operation:
            methods: ["GET"]
            paths: ["/metrics"]
```

## Observability

**Kiali** (topology visualization) and **Jaeger** (distributed tracing) integrate via Istio addons.

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
istioctl dashboard kiali   # service topology
istioctl dashboard jaeger  # trace explorer
```

## Linkerd

### Installation

```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```

### Proxy Injection

```bash
kubectl annotate namespace production linkerd.io/inject=enabled
kubectl rollout restart deployment -n production
```

### ServiceProfile

Per-route metrics and retries for fine-grained traffic control.

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: api-server.production.svc.cluster.local
  namespace: production
spec:
  routes:
    - name: GET /api/v1/users
      condition:
        method: GET
        pathRegex: /api/v1/users
      isRetryable: true
      timeout: 5s
    - name: POST /api/v1/orders
      condition:
        method: POST
        pathRegex: /api/v1/orders
      isRetryable: false
      timeout: 10s
```

## Istio vs Linkerd Comparison

| Feature | Istio | Linkerd |
|---|---|---|
| Proxy | Envoy (C++) | linkerd2-proxy (Rust) |
| Resource footprint | Higher (~50 MB per sidecar) | Lower (~20 MB per sidecar) |
| Feature depth | Comprehensive (routing, policy, telemetry) | Focused (reliability, observability) |
| Multi-cluster | Native multi-cluster with trust domains | Mirror-based multi-cluster |
| mTLS | Configurable per namespace/workload | On by default, automatic |
| Traffic management | Advanced (fault injection, mirroring, header routing) | Basic (retries, timeouts, traffic splits) |
| Learning curve | Steep — many CRDs and configuration options | Gentle — minimal configuration |
| Community | CNCF graduated, large ecosystem | CNCF graduated, opinionated design |

## Best Practices

1. Start with `PERMISSIVE` mTLS mode during mesh adoption, then enforce `STRICT` per namespace once all services have sidecars injected.
2. Configure circuit breakers on every external dependency to prevent cascade failures from slow or unhealthy upstreams.
3. Set explicit timeouts and retries on all VirtualServices — never rely on infinite defaults that mask latency issues.
4. Use traffic mirroring to validate new versions with real production traffic before shifting any live requests.
5. Enable distributed tracing (Jaeger/Zipkin) from day one — retrofitting trace propagation headers is expensive.
6. Pin consistent Istio/Linkerd versions across all clusters and upgrade control planes before data planes.
7. Roll out mesh injection namespace-by-namespace rather than cluster-wide to contain blast radius.
8. Monitor sidecar proxy CPU and memory usage — set resource limits to prevent proxy containers from starving application containers.
