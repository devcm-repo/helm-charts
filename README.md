## helm charts

```shell
helm repo add devcm https://devcm-repo.github.io/helm-charts
```

### charts
- aiapi（New API + CPA + nginx/njs，统一入口包含模型目录、文档与安装脚本）
- sing-box
- tailscale-derp
- rustdesk-server

AIAPI 迁移、TLS 和 Basic Auth 配置见 [aiapi README](charts/aiapi/README.md)。Deployment、Service、PVC 由固定版本的 bjw-s common 生成。先运行 `helm dependency build charts/aiapi`，再运行 `helm lint charts/aiapi --strict`、`python3 tests/test_aiapi_resources.py charts/aiapi` 和 `python3 tests/test_aiapi_nginx.py charts/aiapi`（需要 PyYAML）。
