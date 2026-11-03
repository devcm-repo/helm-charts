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
    printf 'Error: 无法识别 AIAPI 站点，请通过 /getstart/claude-code 安装脚本\n' >&2
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
EST_ANTHROPIC_BASE_URL="${EST_ANTHROPIC_BASE_URL:-${EST_CLAUDE_BASE_URL:-}}"
EST_MODEL="${EST_MODEL:-gpt-5.6-sol}"

write_minimal_settings_json() {
  api_key_json="$(aiapi_escape_json "$EST_API_KEY")"
  base_url_json="$(aiapi_escape_json "$EST_ANTHROPIC_BASE_URL")"
  model_json="$(aiapi_escape_json "$EST_MODEL")"

  {
    printf '{\n'
    printf '  "env": {\n'
    printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$base_url_json"
    printf '    "ANTHROPIC_AUTH_TOKEN": "%s",\n' "$api_key_json"
    printf '    "ANTHROPIC_MODEL": "%s",\n' "$model_json"
    printf '    "ANTHROPIC_SMALL_FAST_MODEL": "%s",\n' "$model_json"
    printf '    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"\n'
    printf '  }\n'
    printf '}\n'
  } > "$SETTINGS_TMP"
}

merge_settings_with_node() {
  SETTINGS_FILE="$SETTINGS_FILE" SETTINGS_TMP="$SETTINGS_TMP" \
  EST_API_KEY="$EST_API_KEY" EST_ANTHROPIC_BASE_URL="$EST_ANTHROPIC_BASE_URL" EST_MODEL="$EST_MODEL" \
  node <<'NODE'
const fs = require("fs");

const source = process.env.SETTINGS_FILE;
const target = process.env.SETTINGS_TMP;
const raw = fs.existsSync(source) ? fs.readFileSync(source, "utf8").trim() : "";
const settings = raw ? JSON.parse(raw) : {};

if (!settings || Array.isArray(settings) || typeof settings !== "object") {
  throw new Error("Claude Code settings.json 必须是 JSON 对象");
}

if (!settings.env || Array.isArray(settings.env) || typeof settings.env !== "object") {
  settings.env = {};
}

settings.env.ANTHROPIC_BASE_URL = process.env.EST_ANTHROPIC_BASE_URL;
settings.env.ANTHROPIC_AUTH_TOKEN = process.env.EST_API_KEY;
settings.env.ANTHROPIC_MODEL = process.env.EST_MODEL;
settings.env.ANTHROPIC_SMALL_FAST_MODEL = process.env.EST_MODEL;
settings.env.CLAUDE_CODE_ATTRIBUTION_HEADER = "0";

fs.writeFileSync(target, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });
NODE
}

merge_settings_with_python() {
  SETTINGS_FILE="$SETTINGS_FILE" SETTINGS_TMP="$SETTINGS_TMP" \
  EST_API_KEY="$EST_API_KEY" EST_ANTHROPIC_BASE_URL="$EST_ANTHROPIC_BASE_URL" EST_MODEL="$EST_MODEL" \
  python3 <<'PY'
import json
import os

source = os.environ["SETTINGS_FILE"]
target = os.environ["SETTINGS_TMP"]

if os.path.exists(source):
    with open(source, "r", encoding="utf-8") as handle:
        raw = handle.read().strip()
else:
    raw = ""

settings = json.loads(raw) if raw else {}
if not isinstance(settings, dict):
    raise SystemExit("Claude Code settings.json 必须是 JSON 对象")

env = settings.get("env")
if not isinstance(env, dict):
    env = {}
    settings["env"] = env

env["ANTHROPIC_BASE_URL"] = os.environ["EST_ANTHROPIC_BASE_URL"]
env["ANTHROPIC_AUTH_TOKEN"] = os.environ["EST_API_KEY"]
env["ANTHROPIC_MODEL"] = os.environ["EST_MODEL"]
env["ANTHROPIC_SMALL_FAST_MODEL"] = os.environ["EST_MODEL"]
env["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"

with open(target, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

write_settings_json() {
  if [ -s "$SETTINGS_FILE" ]; then
    if command -v node >/dev/null 2>&1; then
      merge_settings_with_node
    elif command -v python3 >/dev/null 2>&1; then
      merge_settings_with_python
    else
      aiapi_die "已有 settings.json，需要 node 或 python3 来安全合并配置"
    fi
  else
    write_minimal_settings_json
  fi

  mv "$SETTINGS_TMP" "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE" 2>/dev/null || true
}

aiapi_resolve_anthropic_base_url
aiapi_require_api_key "$EST_ANTHROPIC_BASE_URL"

CLAUDE_HOME_DIR="$(aiapi_resolve_home "${EST_CLAUDE_HOME:-}" ".claude" "EST_CLAUDE_HOME")"
mkdir -p "$CLAUDE_HOME_DIR"

SETTINGS_FILE="$CLAUDE_HOME_DIR/settings.json"
STAMP="$(aiapi_timestamp)"
SETTINGS_TMP="$(mktemp "$CLAUDE_HOME_DIR/settings.json.tmp.XXXXXX")"
trap 'rm -f "$SETTINGS_TMP"' EXIT HUP INT TERM

aiapi_backup_file "$SETTINGS_FILE" "$STAMP"
write_settings_json
aiapi_save_api_key

printf '\nAIAPI Claude Code 配置已完成。\n'
printf 'Claude Home: %s\n' "$CLAUDE_HOME_DIR"
printf 'Base URL: %s\n' "$EST_ANTHROPIC_BASE_URL"
printf 'Model: %s\n' "$EST_MODEL"
printf '如 Claude Code 正在运行，请重启后使用新配置。\n'
