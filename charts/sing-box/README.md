# sing-box Helm Chart

This Helm Chart deploys a VLESS over WebSocket server behind an Ingress Controller, which terminates TLS.

## Installing the Helm Chart

Run from the repository root, with your sing-box configuration in `config.json`:

```shell
kubectl create namespace proxy
kubectl create secret generic sing-box-config --namespace proxy --from-file=config.json=./config.json
helm install proxy charts/sing-box --namespace proxy -f values.yaml
```

## Helm Chart Configuration Examples

A node-local proxy on each labeled node, using the controller's default TLS certificate for `*.dev.com`. The snippet requires ingress-nginx with snippet annotations enabled.

```yaml
kind: DaemonSet

service:
  internalTrafficPolicy: Local

ingress:
  enabled: true
  className: nginx
  host: "*.dev.com"
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/service-upstream: "true"
    nginx.ingress.kubernetes.io/configuration-snippet: 'if ($http_upgrade != "websocket") { return 404; }'
  tls:
    - hosts: ["*.dev.com"]

nodeSelector:
  devcm-proxy/enabled: "true"
```

For WebSocket Early Data, set `max_early_data: 2048` and `early_data_header_name: "Sec-WebSocket-Protocol"` in the server's WebSocket transport.

To also serve Hysteria2, enable `hysteria2.enabled` and set `hysteria2.tlsSecretName` to a cert-manager TLS Secret. Configure a Hysteria2 inbound on UDP `443`, with `certificate_path: /etc/sing-box-tls/tls.crt` and `key_path: /etc/sing-box-tls/tls.key`. UDP uses a host port on each selected node; keep it free and reachable. TCP WebSocket traffic continues through the Ingress.

For a separate cert-manager certificate, add `cert-manager.io/cluster-issuer: dnspod` to annotations and set `ingress.tls[].secretName` in the same namespace. With `kind: Deployment`, use `replicaCount` to scale and anti-affinity to guarantee separate nodes. Interrupted connections require client reconnection.

## Helm Chart Values

| Key | Description | Default |
|---|---|---|
| `image.repository` | Container image repository. | `ghcr.io/sagernet/sing-box` |
| `image.tag` | Container image tag. | `v1.14.4` |
| `image.pullPolicy` | Kubernetes image pull policy. | `IfNotPresent` |
| `kind` | Workload type: `Deployment` or `DaemonSet`. | `Deployment` |
| `replicaCount` | Number of replicas; only used with `kind: Deployment`. | `1` |
| `configSecretName` | Existing Secret containing `config.json`. | `sing-box-config` |
| `port` | Proxy port; must match the sing-box listener. | `54321` |
| `service.type` | Kubernetes Service type. | `ClusterIP` |
| `service.internalTrafficPolicy` | `Cluster` for all backends, or `Local` for node-local backends. | `Cluster` |
| `hysteria2.enabled` | Expose Hysteria2 on a node UDP host port and mount its TLS Secret. | `false` |
| `hysteria2.port` | UDP listener and host port; must match `config.json`. | `443` |
| `hysteria2.tlsSecretName` | Existing TLS Secret mounted at `/etc/sing-box-tls`. | `""` |
| `ingress.enabled` | Enable the public Ingress. | `false` |
| `ingress.className` | IngressClass name. | `""` |
| `ingress.host` | Ingress hostname; required when enabled. | `""` |
| `ingress.path` | WebSocket path; must match the server/client configuration. | `/vws` |
| `ingress.annotations` | Controller-specific annotations. | `{}` |
| `ingress.tls` | TLS hosts and optional namespace-local Secret references. | `[]` |
| `nodeSelector` | Node labels for the Pod. | `{}` |
| `affinity` | Node/Pod affinity rules. | `{}` |
| `tolerations` | Tolerations for node taints. | `[]` |
| `resources` | Container CPU/memory requests and limits. | `{}` |

Update the configuration Secret and restart the workload to reload it. TLS certificate updates are handled by the Ingress Controller.
