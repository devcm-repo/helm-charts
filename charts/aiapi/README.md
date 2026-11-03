# aiapi Helm Chart

This Helm Chart deploys New API, CLIProxyAPI (CPA), and an nginx/njs gateway, with optional PostgreSQL and Valkey. Requires Kubernetes 1.31 or later.

## Installing the Helm Chart

Run from the repository root, with your CPA configuration in `config.yaml`:

```shell
helm dependency build charts/aiapi
helm install aiapi charts/aiapi --namespace aiapi --create-namespace \
  -f values.yaml --set-file cliproxyapi.config=./config.yaml
```

Prepare the TLS Secret and optional Basic Auth Secret in the `aiapi` namespace. The Basic Auth Secret must contain `cliproxyapi.htpasswd`. CPA configuration is read-only; update it through Helm.

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
| `nginx.enabled` | Enable the nginx/njs gateway. | `true` |
| `nginx.basicAuthSecretName` | Existing Basic Auth Secret; empty denies management UI login. | `""` |
| `newapi.image.repository` | New API container image repository. | `calciumion/new-api` |
| `newapi.sessionSecret` | Session secret; replace before deployment. | `change-me` |
| `newapi.ingress.enabled` | Enable the shared public Ingress. | `true` |
| `newapi.ingress.className` | IngressClass name. | `""` |
| `newapi.ingress.tlsSecretName` | TLS Secret; hosts are derived automatically. | `""` |
| `newapi.ingress.annotations` | Controller-specific body size, streaming and timeout settings. | `{}` |
| `newapi.database.existingSecret.name` | Existing Secret containing `SQL_DSN`; disable bundled PostgreSQL. | `""` |
| `newapi.cache.existingSecret.name` | Existing Secret containing `REDIS_CONN_STRING`; disable bundled Valkey. | `""` |
| `cliproxyapi.image.repository` | CPA container image repository. | `eceasy/cli-proxy-api` |
| `cliproxyapi.config` | CPA YAML configuration; accepts `--set-file`. | See [values.yaml](values.yaml) |
| `cliproxyapi.extraEnv` | Additional CPA environment variables and Secret references. | `[]` |
| `postgresql.enabled` | Deploy bundled PostgreSQL. | `true` |
| `postgresql.auth.password` | PostgreSQL user password; replace before deployment. | `change-me` |
| `valkey.enabled` | Deploy bundled Valkey. | `true` |
| `newapi.persistence.size` | New API data/log volume size. | `2Gi` |
| `cliproxyapi.persistence.size` | CPA auth/log/plugin volume size. | `1Gi` |
| `persistence.storageClass` | StorageClass for application volumes. | `""` |
| `nodeSelector` | Node labels for the application Pods. | `{}` |
| `affinity` | Node/Pod affinity rules for the application Pods. | `{}` |

See [values.yaml](values.yaml) for all options. Uninstalling this chart deletes its New API/CPA PVCs; back up data first.
