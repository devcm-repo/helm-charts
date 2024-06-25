# tailscale-derp Helm Chart

This Helm Chart is a Tailscale container deployment for a tailnet relay server (DERP).

## Installing the Helm Chart

```shell
helm repo add tailscale https://devcm-repo.github.io/helm-charts
helm install tailscale-derp tailscale/tailscale-derp
```

## Helm Chart Configuration Examples

A working configuration:

```yaml
hostname: derp.dev.cm

nodeSelector:
  topology.kubernetes.io/region: cn-hk
```

## Helm Chart Values

| Key | Description | Default |
|---|---|---|
| `image.name` | Name of the container image to use. | `docker.io/sspreitzer/tailscale-derp` |
| `image.pullPolicy` | Kubernetes pullPolicy to use for starting the container image. | `IfNotPresent` |
| `service.type` | Kubernetes Service type. | `LoadBalancer` |
| `service.annotations` | A map/dict of Kubernetes Service annotations. | `{}` |
| `nodeSelector` | A map/dict of Kubernetes Pod nodeSelector node labels. | `{}` |
| `affinity` | A map/dict of Kubernetes Pod affinity rules. | `{}` |
| `tailscale.hostname` | Tailscale hostname | `Release.Name` |
| `tailscale.auth_key` | Tailscale auth_key | `''` |
| `drep.hostname` | Derp server hostname | `'derp.examples.com'` |
| `drep.verify_clients` | Derp server will enable authentication | `true` |
