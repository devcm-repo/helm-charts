# CortenDesk

One container runs the console, ID server and relay. SQLite and server keys live
in a dedicated `/data` PVC, retained on uninstall. No external database is needed.
The single replica uses `Recreate` because SQLite and host ports cannot be shared.

Create a Kubernetes Secret containing `CORTENDESK_ADMIN_USER` and
`CORTENDESK_ADMIN_PASSWORD`, then reference it through `envFrom` before exposing
the console. These variables set the first account on an empty database.

```sh
helm install cortendesk ./charts/cortendesk \
  --set appUrl=https://cortendesk.example.com \
  --set ingress.enabled=true \
  --set ingress.host=cortendesk.example.com \
  --set 'envFrom[0].secretRef.name=cortendesk-env'
```

```yaml
envFrom:
  - secretRef:
      name: cortendesk-env
env:
  - name: SESSION_SECURE_COOKIE
    value: "true"
```

The Ingress routes everything, including `/ws/id` and `/ws/relay`, to port 8080;
the image bridges WebSockets internally. Configure TLS and long proxy timeouts
on the ingress controller. Direct clients use the node's `hostPorts`; advertise
changed ports through `CORTENDESK_ID_SERVER` and `CORTENDESK_RELAY_SERVER` in `env`.

Keep the image's default HTTP port (8080), embedded server and SQLite database
path. Set SSO and device access policies in the console. Secrets, settings and
keys under `/data` survive Pod replacement.
