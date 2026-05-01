# aiapi

Deploys New API and CLIProxyAPI. PostgreSQL and Valkey are provided through upstream Bitnami Helm chart dependencies by default.

```shell
helm dependency update ./charts/aiapi
helm install aiapi ./charts/aiapi
```

For production, override at least:

- `newapi.sessionSecret`
- `postgresql.auth.password`
- `cliproxyapi.config`
- `newapi.frontendBaseUrl`

Use the bundled dependencies:

```yaml
postgresql:
  enabled: true
  auth:
    username: newapi
    password: change-me
    database: newapi

valkey:
  enabled: true
  architecture: standalone
  auth:
    enabled: false
```

Use external PostgreSQL and Valkey/Redis by disabling the dependencies and providing the New API environment variables as values:

```yaml
postgresql:
  enabled: false
valkey:
  enabled: false

newapi:
  database:
    dsn: postgres://newapi:password@postgres.example.com:5432/newapi?sslmode=require
  cache:
    redisConnString: redis://:password@valkey.example.com:6379/0
```

For production, prefer storing the complete connection strings in an existing Kubernetes Secret:

```yaml
postgresql:
  enabled: false
valkey:
  enabled: false

newapi:
  database:
    existingSecret:
      name: aiapi-external-connections
      key: SQL_DSN
  cache:
    existingSecret:
      name: aiapi-external-connections
      key: REDIS_CONN_STRING
```

`newapi.database.*` renders `SQL_DSN`; `newapi.cache.*` renders `REDIS_CONN_STRING`. The older `newapi.sqlDsn` and `newapi.redisConnString` values still work for compatibility.

`cliproxyapi.ingress` is disabled by default. If exposing it under `/cpa`, add the rewrite annotations required by your Ingress controller and set `remote-management.allow-remote` in `cliproxyapi.config` intentionally.
