#!/bin/sh

aiapi_die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

aiapi_is_toml_key() {
  case "$1" in
    ''|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

aiapi_escape_toml() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

aiapi_escape_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

aiapi_backup_file() {
  if [ -f "$1" ]; then
    cp "$1" "$1.bak.$2"
  fi
}

aiapi_resolve_token_url() {
  if [ -n "${EST_SITE_ORIGIN:-}" ]; then
    EST_SITE_ORIGIN="${EST_SITE_ORIGIN%/}"
  fi

  if [ -z "${EST_TOKEN_URL:-}" ] && [ -n "${EST_SITE_ORIGIN:-}" ]; then
    EST_TOKEN_URL="$EST_SITE_ORIGIN/keys"
  fi
}

aiapi_resolve_openai_base_url() {
  aiapi_resolve_token_url

  if [ -z "${EST_API_BASE_URL:-}" ]; then
    [ -n "${EST_SITE_ORIGIN:-}" ] || aiapi_die "无法确定 AIAPI 站点，请使用文档上的安装命令，或设置 EST_API_BASE_URL"
    EST_API_BASE_URL="$EST_SITE_ORIGIN/v1"
  fi
}

aiapi_resolve_anthropic_base_url() {
  aiapi_resolve_token_url

  if [ -z "${EST_ANTHROPIC_BASE_URL:-}" ]; then
    [ -n "${EST_SITE_ORIGIN:-}" ] || aiapi_die "无法确定 AIAPI 站点，请使用文档上的安装命令，或设置 EST_ANTHROPIC_BASE_URL"
    EST_ANTHROPIC_BASE_URL="$EST_SITE_ORIGIN"
  fi
}

aiapi_prompt_api_key() {
  if [ -n "${EST_API_KEY:-}" ]; then
    return
  fi

  previous_api_key=""
  if [ -r "$AIAPI_KEY_CACHE_FILE" ]; then
    cached_origin=""
    {
      IFS= read -r cached_origin || true
      IFS= read -r previous_api_key || true
    } < "$AIAPI_KEY_CACHE_FILE"
    if [ "$cached_origin" != "$AIAPI_KEY_ORIGIN" ]; then
      previous_api_key=""
    fi
  fi
  if [ -r /dev/tty ] && [ -w /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; then
    if [ -n "${EST_TOKEN_URL:-}" ]; then
      printf 'AIAPI API Key 获取地址: %s\n' "$EST_TOKEN_URL" > /dev/tty
    else
      printf 'AIAPI API Key 获取地址: 当前 AIAPI 后台 /keys\n' > /dev/tty
    fi
    if [ -n "$previous_api_key" ]; then
      printf '已检测到原 API Key；不更改请直接回车，默认使用原 key。\n' > /dev/tty
    fi
    printf '请输入 EST_API_KEY: ' > /dev/tty
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r EST_API_KEY < /dev/tty || true
    stty echo < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
    EST_API_KEY="${EST_API_KEY:-$previous_api_key}"
  elif [ -n "$previous_api_key" ]; then
    printf '已检测到原 API Key，默认使用原 key。\n'
    EST_API_KEY="$previous_api_key"
  else
    aiapi_die "未提供 EST_API_KEY，且无法打开交互式终端。请先设置 EST_API_KEY。"
  fi
}

aiapi_require_api_key() {
  [ -n "${HOME:-}" ] || aiapi_die "未找到 HOME，无法保存 API Key 缓存"
  AIAPI_KEY_CACHE_FILE="$HOME/.aiapi/credentials"
  api_key_authority="${1#*://}"
  AIAPI_KEY_ORIGIN="${1%%://*}://${api_key_authority%%/*}"
  aiapi_prompt_api_key
  [ -n "${EST_API_KEY:-}" ] || aiapi_die "EST_API_KEY 不能为空"

  case "$EST_API_KEY" in
    *'
'*|*"$(printf '\r')"*)
      aiapi_die "EST_API_KEY 不能包含换行"
      ;;
  esac
}

aiapi_save_api_key() (
  umask 077
  cache_dir="$HOME/.aiapi"
  mkdir -p "$cache_dir"
  chmod 700 "$cache_dir"
  cache_tmp="$(mktemp "$cache_dir/credentials.tmp.XXXXXX")"
  trap 'rm -f "$cache_tmp"' EXIT HUP INT TERM
  printf '%s\n%s\n' "$AIAPI_KEY_ORIGIN" "$EST_API_KEY" > "$cache_tmp"
  mv -f "$cache_tmp" "$AIAPI_KEY_CACHE_FILE"
)

aiapi_resolve_home() {
  current_home="$1"
  default_dir="$2"
  env_name="$3"

  if [ -n "$current_home" ]; then
    printf '%s\n' "$current_home"
    return
  fi

  [ -n "${HOME:-}" ] || aiapi_die "未找到 HOME，请设置 $env_name"
  printf '%s/%s\n' "$HOME" "$default_dir"
}

aiapi_timestamp() {
  date +%Y%m%d%H%M%S
}

aiapi_merge_toml_table() {
  if [ ! -r "$1" ]; then
    printf '[%s]\n%s\n' "$4" "$5"
    return
  fi

  awk -v root_names="$2" -v removed_tables="$3" -v merged_table="$4" -v managed_lines="$5" '
    function key_of(line, key) {
      if (line !~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/) {
        return ""
      }
      key = line
      sub(/=.*/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      return key
    }

    BEGIN {
      in_root = 1
      for (i = 1; i <= split(root_names, root_parts, /[[:space:]]+/); i++) {
        removed_roots[root_parts[i]] = 1
      }
      for (i = 1; i <= split(removed_tables, table_parts, /[[:space:]]+/); i++) {
        removed_table[table_parts[i]] = 1
      }
      managed_count = split(managed_lines, managed_parts, /\n/)
      for (i = 1; i <= managed_count; i++) {
        managed_key[key_of(managed_parts[i])] = 1
      }
    }

    /^[[:space:]]*\[/ {
      in_root = 0
      skip_section = 0
      header = $0
      sub(/[[:space:]]*#.*/, "", header)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
      table = header
      sub(/^\[/, "", table)
      sub(/\]$/, "", table)
      in_merged = (table == merged_table)
      skip_section = removed_table[table]
      if (in_merged || skip_section) {
        next
      }
      print
      next
    }

    skip_section {
      next
    }

    in_root && removed_roots[key_of($0)] {
      next
    }

    in_merged {
      key = key_of($0)
      if (managed_key[key]) {
        next
      }
      if (key == "") {
        merged_lines[++merged_count] = $0
      } else if (merged_index[key]) {
        merged_lines[merged_index[key]] = $0
      } else {
        merged_index[key] = ++merged_count
        merged_lines[merged_count] = $0
      }
      next
    }

    {
      print
    }

    END {
      print ""
      print "[" merged_table "]"
      for (i = 1; i <= merged_count; i++) {
        print merged_lines[i]
      }
      for (i = 1; i <= managed_count; i++) {
        print managed_parts[i]
      }
    }
  ' "$1"
}
