#!/bin/sh
set -eu

EST_SITE_ORIGIN="${EST_SITE_ORIGIN:-__AIAPI_SITE_ORIGIN__}"
AIAPI_SITE_ORIGIN_PLACEHOLDER='__AIAPI_SITE_''ORIGIN__'

load_aiapi_common() {
  if [ -n "${EST_AIAPI_COMMON_SH:-}" ]; then
    . "$EST_AIAPI_COMMON_SH"
    return
  fi

  if [ -z "${EST_SITE_ORIGIN:-}" ] || [ "$EST_SITE_ORIGIN" = "$AIAPI_SITE_ORIGIN_PLACEHOLDER" ]; then
    printf 'Error: 无法识别 AIAPI 站点，请通过 /getstart/codex 安装脚本\n' >&2
    exit 1
  fi

  common_url="${EST_SITE_ORIGIN%/}/getstart/lib/common"
  common_tmp="$(mktemp "${TMPDIR:-/tmp}/aiapi-common.XXXXXX")" || exit 1

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$common_url" -o "$common_tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$common_tmp" "$common_url"
  else
    rm -f "$common_tmp"
    printf 'Error: 需要 curl 或 wget 下载公共脚本\n' >&2
    exit 1
  fi

  . "$common_tmp"
  rm -f "$common_tmp"
}

load_aiapi_common

EST_TOKEN_URL="${EST_TOKEN_URL:-}"
EST_API_BASE_URL="${EST_API_BASE_URL:-}"
EST_PROVIDER_ID="${EST_PROVIDER_ID:-eshetang}"
EST_LEGACY_PROVIDER_ID="${EST_LEGACY_PROVIDER_ID:-$EST_PROVIDER_ID}"
EST_LEGACY_PROFILE="${EST_LEGACY_PROFILE:-${EST_PROFILE:-third_party}}"
EST_MODEL="${EST_MODEL:-gpt-6.1-sol}"
EST_WIRE_API="${EST_WIRE_API:-responses}"
USE_MODEL_CATALOG=0

download_model_catalog() {
  printf '正在获取三方模型...\n'
  if command -v curl >/dev/null 2>&1 && curl -fsSL -H "Authorization: Bearer $EST_API_KEY" "$CATALOG_URL" -o "$CATALOG_TMP"; then
    :
  elif command -v wget >/dev/null 2>&1 && wget -qO "$CATALOG_TMP" --header="Authorization: Bearer $EST_API_KEY" "$CATALOG_URL"; then
    :
  else
    printf '获取三方模型失败，已跳过模型目录配置。\n' >&2
    return
  fi

  if ! awk -F'"slug"[[:space:]]*:[[:space:]]*"' '
    {
      for (i = 2; i <= NF; i++) {
        slug = tolower($i)
        sub(/".*/, "", slug)
        sub(/^.*\//, "", slug)
        if (slug !~ /gpt/) {
          found = 1
          exit
        }
      }
    }
    END { exit !found }
  ' "$CATALOG_TMP"; then
    printf '未获取到非 GPT 系列模型，已跳过模型目录配置。\n'
    return
  fi

  aiapi_backup_file "$CATALOG_FILE" "$STAMP"
  mv "$CATALOG_TMP" "$CATALOG_FILE"
  chmod 600 "$CATALOG_FILE" 2>/dev/null || true
  USE_MODEL_CATALOG=1
}

write_config_toml() {
  model_value="$(aiapi_escape_toml "$EST_MODEL")"
  catalog_value="$(aiapi_escape_toml "$CATALOG_FILE")"
  provider_value="$(aiapi_escape_toml "$EST_PROVIDER_ID")"
  base_url_value="$(aiapi_escape_toml "$EST_API_BASE_URL")"
  wire_api_value="$(aiapi_escape_toml "$EST_WIRE_API")"
  api_key_value="$(aiapi_escape_toml "$EST_API_KEY")"

  aiapi_merge_toml_table \
    "$CONFIG_FILE" \
    'model model_provider model_catalog_json openai_base_url profile web_search' \
    "profiles.$EST_LEGACY_PROFILE model_providers.$EST_PROVIDER_ID model_providers.$EST_LEGACY_PROVIDER_ID" \
    agents \
    'max_concurrent_threads_per_session = 12' > "$CONFIG_TMP"

  aiapi_merge_toml_table \
    "$CONFIG_TMP" \
    '' \
    '' \
    features \
    'remote_compaction_v2 = true' > "$FILTERED_TMP"

  aiapi_merge_toml_table \
    "$FILTERED_TMP" \
    '' \
    '' \
    features \
    'multi_agent_v2 = true' > "$MERGED_TMP"

  {
    printf 'model = "%s"\n' "$model_value"
    printf 'model_provider = "%s"\n' "$provider_value"
    if [ "$USE_MODEL_CATALOG" = 1 ]; then
      printf 'model_catalog_json = "%s"\n' "$catalog_value"
    fi
    printf 'web_search = "live"\n\n'

    if grep -q '[^[:space:]]' "$MERGED_TMP"; then
      sed '/./,$!d' "$MERGED_TMP"
      printf '\n'
    fi

    printf '[model_providers.%s]\n' "$EST_PROVIDER_ID"
    printf 'name = "OpenAI"\n'
    printf 'base_url = "%s"\n' "$base_url_value"
    printf 'wire_api = "%s"\n' "$wire_api_value"
    printf 'requires_openai_auth = true\n'
    printf 'supports_websockets = true\n'
    printf 'supports_standalone_web_search = true\n'
    printf 'experimental_bearer_token = "%s"\n' "$api_key_value"
  } > "$CONFIG_TMP"

  mv "$CONFIG_TMP" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
}

aiapi_is_toml_key "$EST_PROVIDER_ID" || aiapi_die "EST_PROVIDER_ID 只能包含字母、数字和下划线"

aiapi_resolve_openai_base_url
EST_API_BASE_URL="${EST_API_BASE_URL%/}"
case "$EST_API_BASE_URL" in
  */codex)
    EST_API_BASE_URL="${EST_API_BASE_URL%/codex}"
    ;;
esac
aiapi_require_api_key "$EST_API_BASE_URL"

CODEX_HOME_DIR="$(aiapi_resolve_home "${EST_CODEX_HOME:-}" ".codex" "EST_CODEX_HOME")"
mkdir -p "$CODEX_HOME_DIR"

CONFIG_FILE="$CODEX_HOME_DIR/config.toml"
CATALOG_FILE="$CODEX_HOME_DIR/aiapi-models.json"
CATALOG_URL="${EST_API_BASE_URL%/}/codex/models"
STAMP="$(aiapi_timestamp)"

CONFIG_TMP="$(mktemp "$CODEX_HOME_DIR/config.toml.tmp.XXXXXX")"
FILTERED_TMP="$(mktemp "$CODEX_HOME_DIR/config.filtered.tmp.XXXXXX")"
MERGED_TMP="$(mktemp "$CODEX_HOME_DIR/config.merged.tmp.XXXXXX")"
CATALOG_TMP="$(mktemp "$CODEX_HOME_DIR/aiapi-models.json.tmp.XXXXXX")"
trap 'rm -f "$CONFIG_TMP" "$FILTERED_TMP" "$MERGED_TMP" "$CATALOG_TMP"' EXIT HUP INT TERM

download_model_catalog
aiapi_backup_file "$CONFIG_FILE" "$STAMP"
write_config_toml
aiapi_save_api_key

printf '\nAIAPI Codex 配置已完成。\n'
printf 'Codex Home: %s\n' "$CODEX_HOME_DIR"
printf 'Provider: %s\n' "$EST_PROVIDER_ID"
printf 'Base URL: %s\n' "$EST_API_BASE_URL"
if [ "$USE_MODEL_CATALOG" = 1 ]; then
  printf 'Model Catalog: %s\n' "$CATALOG_FILE"
fi
printf 'Model: %s\n' "$EST_MODEL"
printf '如 Codex 正在运行，请重启 Codex 后使用新配置。\n'
