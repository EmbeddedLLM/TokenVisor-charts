# Network

TokenVisor uses the Kubernetes Gateway API with Cilium as the gateway controller.

## Gateway

The chart creates a `Gateway` resource (`cilium-gateway`) with an HTTP listener on port 80 by default.

## TLS Termination

Choose one approach depending on where TLS is terminated in your infrastructure. Place your overrides in a `values.network.yaml` file and add it to your install/upgrade command:

```bash
helm upgrade --install tokenvisor . \
  -n tokenvisor \
  -f values.yaml \
  ... \
  -f values.network.yaml
```

### Option A: Terminate TLS externally (reverse proxy or cloud load balancer)

Use this if TLS is already terminated upstream — for example at an Nginx/Caddy reverse proxy, a cloud load balancer, or a Cloudflare tunnel — and the cluster only receives plain HTTP traffic.

In this case, do not enable the HTTPS listener. Leave the default:

```yaml
network:
  gateway:
    https:
      enabled: false
```

Set Studio's origin to match how users reach it externally:

```yaml
studio:
  config:
    HOST: "yourdomain.com"
    ORIGIN: "https://yourdomain.com"
    USE_SECURE_COOKIES: "true"
```

`USE_SECURE_COOKIES` should still be `"true"` if users reach the site over HTTPS, even if the cluster itself only sees HTTP internally.

### Option B: Terminate TLS inside the cluster (Cilium Gateway + cert-manager)

Use this if traffic enters the cluster unencrypted (e.g. bare-metal, no external load balancer doing TLS offload) and you want the cluster to handle HTTPS itself using cert-manager and Let's Encrypt.

This option requires **cert-manager** and a configured `ClusterIssuer` (or `Issuer`). The chart does **not** install these — complete the setup below before enabling the HTTPS listener.

#### 1. Install cert-manager

Follow the [official guide](https://cert-manager.io/docs/installation/) or use Helm:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.2 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

#### 2. Create a ClusterIssuer

Create an ACME `ClusterIssuer` that uses the HTTP-01 challenge solver, point the solver at the `Gateway`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: you@example.com # replace with your email
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: cilium-gateway
                namespace: tokenvisor
                kind: Gateway
```

#### 3. Create a Certificate

Request a certificate in the `tokenvisor` namespace. The `secretName` is where cert-manager will store the resulting TLS key pair:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tokenvisor-tls
  namespace: tokenvisor
spec:
  secretName: tokenvisor-tls-secret # must match tlsSecretName below
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - yourdomain.com
```

Verify the certificate is issued:

```bash
kubectl get certificate -n tokenvisor
```

#### 4. Enable the HTTPS listener

Once cert-manager is running and the `ClusterIssuer` is in place, enable the HTTPS listener in your values override:

```yaml
network:
  gateway:
    https:
      enabled: true
      tlsSecretName: "tokenvisor-tls-secret"
```

`tlsSecretName` must match `spec.secretName` in the `Certificate` resource above. The secret does not need to exist at install time — Cilium will wait for cert-manager to provision it and bring up the HTTPS listener once it appears.

Also update Studio to use HTTPS:

```yaml
studio:
  config:
    HOST: "yourdomain.com"
    ORIGIN: "https://yourdomain.com"
    USE_SECURE_COOKIES: "true"
```

## HTTP listener

The HTTP listener on port 80 is always active regardless of which option you choose. To redirect HTTP to HTTPS when using Option B, configure an `HTTPRoute` with a redirect filter — this is not done automatically by the chart:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tokenvisor-https-redirect
  namespace: tokenvisor
spec:
  parentRefs:
    - name: cilium-gateway
      sectionName: http
  hostnames:
    - yourdomain.com
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

## Exposing behind a firewall (DNAT / SNAT)

Applies only when the gateway is a `LoadBalancer` service (Cilium L2/BGP — i.e. **not** `hostNetwork` mode) and you forward a public IP to its VIP with a firewall.

The return path must be **symmetric**: the reply has to come back through the same firewall so it can reverse the NAT, or the client receives a packet sourced from the (private) VIP and drops the connection. Which `externalTrafficPolicy` to use depends on what NAT your firewall does:

| Firewall does | Set | Client source IP | Why it works |
| --- | --- | --- | --- |
| **DNAT only** (dest → VIP, source kept) | `externalTrafficPolicy: Local` | preserved | Cilium serves the VIP on the node that owns it — no cross-node hop, no in-cluster SNAT — so ingress and egress stay on one node. |
| **SNAT + DNAT** (full NAT — also rewrites source) | `externalTrafficPolicy: Cluster` (default) | lost (firewall IP) | the firewall's SNAT forces every reply back through it, so symmetry holds even if Cilium forwards across nodes. |

Avoid the broken combination — **`Cluster` + DNAT-only**: the reply is sourced from the VIP and sent out the node's default route; if that is not the firewall it is never un-NAT'd and the connection drops. So if your firewall can only do DNAT, use `Local`.

Set the policy via the Cilium gateway value (default `Cluster`), not by editing the generated Service (the operator reverts manual edits). Set it whichever way you installed Cilium:

**k3d (Helm `--set`, see `docs/K3D.md`):**

```bash
helm upgrade --install cilium cilium/cilium -n kube-system --reuse-values \
  --set gatewayAPI.externalTrafficPolicy=Local
```

**RKE2 (`HelmChartConfig`, see `docs/RKE2.md`):**

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    gatewayAPI:
      enabled: true
      externalTrafficPolicy: Local
    ...
```

- Ignored when `gatewayAPI.hostNetwork.enabled=true` (host-network mode has no LoadBalancer VIP — reach it at `node-ip:port` instead).
- `Local` requires a ready gateway endpoint on the announcing node; Cilium's L2 announcement is endpoint-aware and `cilium-envoy` runs as a per-node DaemonSet, so every node qualifies.
