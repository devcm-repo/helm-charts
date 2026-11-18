# aiapi Helm Chart

This Helm Chart deploys New API, CLIProxyAPI (CPA), and an nginx/njs gateway, with optional PostgreSQL and Valkey. Requires Kubernetes 1.28 or later.

## Installing the Helm Chart

Run from the repository root, with your CPA configuration in `config.yaml`:

```shell
helm dependency build charts/aiapi
helm install aiapi charts/aiapi --namespace aiapi --create-namespace \
  -f values.yaml --set-file cliproxyapi.config=./config.yaml
```

Prepare the TLS Secret and optional Basic Auth Secret in the `aiapi` namespace. The Basic Auth Secret must contain `cliproxyapi.htpasswd`. CPA configuration is read-only; update it through Helm, or use `existingSecret` to keep credentials outside Helm values.

For the infra environment, `python3 scripts/render-secrets.py /path/to/aiapi` reads `.env` and `values.yaml` and outputs the required Kubernetes Secrets. It requires PyYAML. Apply the generated Secrets before upgrading Helm; the chart hashes the existing configuration Secret during an upgrade to refresh mounted configuration.

## Helm Chart Configuration Examples

A working configuration (replace the placeholder secrets):

```yaml
publicUrl: https://aiapi.eshetang.com

newapi:
  sessionSecret: "<session-secret>"
  ingress:
    className: nginx
    tlsSecretName: aiapi-tls

nginx:
  basicAuthSecretName: aiapi-nginx-auth

postgresql:
  auth:
    password: "<database-password>"

nodeSelector:
  topology.kubernetes.io/region: cn-hk
```

The gateway serves `/doc/`, `/getstart/*`, `/cpa/*`, and `/v1/codex/models`. Remote CPA management also requires `remote-management.allow-remote: true` and a management key in `config.yaml`.

## Helm Chart Values

| Key | Description | Default |
|---|---|---|
| `publicUrl` | Public URL; also determines the Ingress host. | `https://aiapi.eshetang.com` |
| `existingSecret` | Existing Secret with `newapi-session-secret` and `cliproxyapi-config.yaml`; disables the chart-managed Secret. | `""` |
| `nginx.enabled` | Enable the nginx/njs gateway. | `true` |
| `nginx.basicAuthSecretName` | Existing Basic Auth Secret; empty denies management UI login. | `""` |
| `newapi.updateStrategy` | Kubernetes Deployment strategy with optional rolling update limits. | `type: Recreate` |
| `newapi.image.repository` | New API container image repository. | `calciumion/new-api` |
| `newapi.sessionSecret` | Session secret; replace before deployment. | `change-me` |
| `newapi.ingress.enabled` | Enable the shared public Ingress. | `true` |
| `newapi.ingress.className` | IngressClass name. | `""` |
| `newapi.ingress.tlsSecretName` | TLS Secret; hosts are derived automatically. | `""` |
| `newapi.ingress.annotations` | Controller-specific body size, streaming and timeout settings. | `{}` |
| `newapi.database.existingSecret.name` | Existing Secret containing `SQL_DSN`; disable bundled PostgreSQL. | `""` |
| `newapi.cache.existingSecret.name` | Existing Secret containing `REDIS_CONN_STRING`; disable bundled Valkey. | `""` |
| `cliproxyapi.updateStrategy` | Kubernetes Deployment strategy with optional rolling update limits. | `type: Recreate` |
| `cliproxyapi.waitForKvLock` | Wait for the default local bbolt database to unlock before starting CPA. | `false` |
| `cliproxyapi.image.repository` | CPA container image repository. | `eceasy/cli-proxy-api` |
| `cliproxyapi.config` | CPA YAML configuration; accepts `--set-file`. | See [values.yaml](values.yaml) |
| `cliproxyapi.extraEnv` | Additional CPA environment variables and Secret references. | `[]` |
| `cliproxyapi.caSecretName` | Existing Secret containing the complete `ca-certificates.crt` trust bundle. | `""` |
| `cliproxyapi.proxy.enabled` | Add a sing-box client sidecar to the CPA Pod; configure CPA to use `127.0.0.1:1080`. | `false` |
| `cliproxyapi.proxy.configSecretName` | Existing Secret with the client's `config.json`; mounted only into sing-box. | `""` |
| `cliproxyapi.proxy.image` | sing-box sidecar image settings. | `ghcr.io/sagernet/sing-box:v1.14.4` |
| `postgresql.enabled` | Deploy bundled PostgreSQL. | `true` |
| `postgresql.auth.password` | PostgreSQL user password; replace before deployment. | `change-me` |
| `valkey.enabled` | Deploy bundled Valkey. | `true` |
| `newapi.persistence.size` | New API data/log volume size. | `2Gi` |
| `cliproxyapi.persistence.size` | CPA auth/log/plugin volume size. | `1Gi` |
| `persistence.storageClass` | StorageClass for application volumes. | `""` |
| `nodeSelector` | Node labels for the application Pods. | `{}` |
| `affinity` | Node/Pod affinity rules for the application Pods. | `{}` |

For a rolling update using CPA's default local bbolt store, use one replica, `maxSurge: 0`, `maxUnavailable: 1`, and `cliproxyapi.waitForKvLock: true`. CPA is temporarily unavailable while the old replica shuts down and the new Pod acquires the database lock.

See [values.yaml](values.yaml) for all options. Uninstalling this chart deletes its New API/CPA PVCs; back up data first.
