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
| `hostNetwork` | This service will be disabled when hostNetwork is enableds. | `false` |
| `nodeSelector` | A map/dict of Kubernetes Pod nodeSelector node labels. | `{}` |
| `extraVolumes` | Extra volumes to add to the deployment. | `[]` |
| `extraVolumeMounts` | Extra volume mounts to add to the container. Normally used with `extraVolumes`. | `[]` |
| `affinity` | A map/dict of Kubernetes Pod affinity rules. | `{}` |
| `derp.hostname` | Derp server hostname. | `'derp.examples.com'` |
| `derp.verify_clients` | Derp server will enable authentication. | `true` |
| `derp.certdir` | Start a derper with your own certificate. | `` |
| `derp.http_port` | The port on which to serve HTTP. Set to -1 to disable. | `80` |
| `derp.https_port` | The port on which to serve HTTPS. | `443` |
| `derp.stun_port` | The UDP port on which to serve STUN. | `3478` |
