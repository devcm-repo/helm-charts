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

A working configuration using the controller's default TLS certificate for `*.node.dev.cm`. The snippet requires ingress-nginx with snippet annotations enabled.

```yaml
replicaCount: 2

ingress:
  enabled: true
  className: nginx
  host: "*.node.dev.cm"
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      if ($http_upgrade != "websocket") {
        return 404;
      }
  tls:
    - hosts: ["*.node.dev.cm"]

nodeSelector:
  topology.kubernetes.io/region: cn-hk
```

For a separate cert-manager certificate, add `cert-manager.io/cluster-issuer: dnspod` to annotations and set `ingress.tls[].secretName` in the same namespace. Multiple replicas need anti-affinity for guaranteed placement on separate nodes; interrupted connections require client reconnection.

## Helm Chart Values

| Key | Description | Default |
|---|---|---|
| `image.repository` | Container image repository. | `ghcr.io/sagernet/sing-box` |
| `image.tag` | Container image tag. | `v1.14.4` |
| `image.pullPolicy` | Kubernetes image pull policy. | `IfNotPresent` |
| `replicaCount` | Number of Deployment replicas. | `1` |
| `configSecretName` | Existing Secret containing `config.json`. | `sing-box-config` |
| `port` | Proxy port; must match the sing-box listener. | `54321` |
| `service.type` | Kubernetes Service type. | `ClusterIP` |
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

Update the configuration Secret and restart the Deployment to reload it. TLS certificate updates are handled by the Ingress Controller.
