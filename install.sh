#!/usr/bin/env bash

set -euo pipefail

PLUGIN_NAME="mem9"
PLUGIN_REPO="mem9-ai/mem9-hermes-plugin"
DEFAULT_API_URL="https://api.mem9.ai"
DEFAULT_AGENT_ID="hermes"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PLUGIN_DIR="$HERMES_HOME/plugins/$PLUGIN_NAME"
HERMES_ENV_FILE="$HERMES_HOME/.env"
MEM9_CONFIG_FILE="$HERMES_HOME/mem9.json"
MEM9_API_URL="${MEM9_API_URL:-}"
MEM9_AGENT_ID="${MEM9_AGENT_ID:-}"
HERMES_PROJECT_HINT="${HERMES_PROJECT_ROOT:-}"
FORCE_INSTALL=0

info() {
  printf -- '-> %s\n' "$*"
}

success() {
  printf 'OK %s\n' "$*"
}

warn() {
  printf 'WARN %s\n' "$*" >&2
}

fail() {
  printf 'ERROR %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || fail "missing required command: $1"
}

is_hermes_project_root() {
  local candidate="$1"
  [ -n "$candidate" ] || return 1
  [ -f "$candidate/hermes_cli/main.py" ] || return 1
  [ -d "$candidate/plugins/memory" ] || return 1
}

extract_project_path() {
  awk '
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Project:[[:space:]]*/ {
      sub(/^[[:space:]]*Project:[[:space:]]*/, "", $0)
      print
      exit
    }
  '
}

detect_hermes_project_root() {
  local candidate=""
  local output=""

  if is_hermes_project_root "$HERMES_PROJECT_HINT"; then
    printf '%s\n' "$HERMES_PROJECT_HINT"
    return 0
  fi

  if have_cmd hermes; then
    output="$(HERMES_HOME="$HERMES_HOME" hermes version 2>/dev/null || true)"
    candidate="$(printf '%s\n' "$output" | extract_project_path)"
    if is_hermes_project_root "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi

    output="$(HERMES_HOME="$HERMES_HOME" hermes status 2>/dev/null || true)"
    candidate="$(printf '%s\n' "$output" | extract_project_path)"
    if is_hermes_project_root "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in "$HERMES_HOME/hermes-agent" "$HOME/.hermes/hermes-agent"; do
    if is_hermes_project_root "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

read_env_value() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 0
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
    }
    END {
      if (value != "") {
        print value
      }
    }
  ' "$file"
}

read_json_value() {
  local key="$1"
  local file="$2"
  local hermes_python="$3"

  [ -f "$file" ] || return 0
  "$hermes_python" - "$file" "$key" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
key = sys.argv[2]

try:
    payload = json.loads(config_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

value = payload.get(key)
if value is None:
    raise SystemExit(0)
if isinstance(value, str):
    value = value.strip()
if value == "":
    raise SystemExit(0)

print(value)
PY
}

upsert_env_value() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp_file

  mkdir -p "$(dirname "$file")"
  tmp_file="${file}.tmp.$$"

  if [ -f "$file" ]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { updated = 0 }
      index($0, key "=") == 1 {
        if (!updated) {
          print key "=" value
          updated = 1
        }
        next
      }
      { print }
      END {
        if (!updated) {
          print key "=" value
        }
      }
    ' "$file" >"$tmp_file"
  else
    printf '%s=%s\n' "$key" "$value" >"$tmp_file"
  fi

  mv "$tmp_file" "$file"
}

create_api_key() {
  local response

  require_cmd curl
  require_cmd python3

  info "creating a new mem9 API key"
  response="$(
    curl -fsSL \
      --connect-timeout 5 \
      --max-time 20 \
      --retry 2 \
      --retry-delay 1 \
      --retry-connrefused \
      -X POST \
      "${MEM9_API_URL%/}/v1alpha1/mem9s"
  )"

  printf '%s' "$response" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
api_key = (payload.get("id") or "").strip()
if not api_key:
    raise SystemExit("mem9 server did not return an id")
print(api_key)
'
}

verify_api_key() {
  local key="$1"
  local url="$2"

  require_cmd curl

  info "verifying API key connectivity"
  if curl -fsSL \
       --connect-timeout 5 \
       --max-time 10 \
       -H "X-API-Key: $key" \
       -H "Content-Type: application/json" \
       "${url%/}/v1alpha2/mem9s/memories?q=test&limit=1" >/dev/null 2>&1; then
    success "API key is valid"
    return 0
  else
    return 1
  fi
}

get_hermes_python() {
  local hermes_project_root="$1"
  local hermes_python="$hermes_project_root/.venv/bin/python"

  if [ ! -x "$hermes_python" ]; then
    hermes_python="$(command -v python3 || true)"
  fi

  [ -n "$hermes_python" ] || fail "unable to find a Python interpreter for Hermes"
  printf '%s\n' "$hermes_python"
}

write_provider_config() {
  local hermes_python="$1"

  "$hermes_python" - "$MEM9_CONFIG_FILE" "$MEM9_API_URL" "$MEM9_AGENT_ID" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
api_url = sys.argv[2]
agent_id = sys.argv[3]

existing = {}
if config_path.exists():
    try:
        existing = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        existing = {}

existing.pop("api_key", None)
existing["api_url"] = api_url
existing["agent_id"] = agent_id

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
PY
}

ensure_memory_symlink() {
  local hermes_project_root="$1"
  local memory_dir="$hermes_project_root/plugins/memory"
  local memory_link="$memory_dir/$PLUGIN_NAME"

  mkdir -p "$memory_dir"

  if [ -L "$memory_link" ]; then
    if [ "$(readlink "$memory_link")" = "$PLUGIN_DIR" ]; then
      success "memory symlink already points at $PLUGIN_DIR"
      return 0
    fi

    rm "$memory_link"
    ln -s "$PLUGIN_DIR" "$memory_link"
    success "updated memory symlink at $memory_link"
    return 0
  fi

  if [ -e "$memory_link" ]; then
    fail "found an existing path at $memory_link; move it away before enabling mem9"
  fi

  ln -s "$PLUGIN_DIR" "$memory_link"
  success "linked mem9 into $memory_link"
}

cleanup_memory_symlink() {
  local hermes_project_root="$1"
  local memory_link="$hermes_project_root/plugins/memory/$PLUGIN_NAME"

  if [ -L "$memory_link" ] && [ "$(readlink "$memory_link")" = "$PLUGIN_DIR" ]; then
    rm "$memory_link"
    success "removed mem9 symlink from $memory_link"
  fi
}

activate_provider_with_python() {
  local hermes_project_root="$1"
  local hermes_python="$2"

  HERMES_HOME="$HERMES_HOME" "$hermes_python" - "$hermes_project_root" <<'PY'
import sys

project_root = sys.argv[1]
sys.path.insert(0, project_root)

from hermes_cli.config import load_config, save_config

config = load_config()
memory_config = config.get("memory")
if not isinstance(memory_config, dict):
    memory_config = {}
    config["memory"] = memory_config

memory_config["provider"] = "mem9"
save_config(config)
PY
}

activate_provider() {
  local hermes_project_root="$1"
  local hermes_python="$2"

  if have_cmd hermes; then
    if HERMES_HOME="$HERMES_HOME" hermes config set memory.provider "$PLUGIN_NAME" >/dev/null; then
      success "activated memory.provider=$PLUGIN_NAME via hermes CLI"
      return 0
    fi
    warn "hermes config set failed; trying Python fallback"
  fi

  if activate_provider_with_python "$hermes_project_root" "$hermes_python"; then
    success "activated memory.provider=$PLUGIN_NAME via Python fallback"
    return 0
  fi

  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE_INSTALL=1
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

have_cmd hermes || fail "hermes command is required; install Hermes first"

install_args=()
if [ "$FORCE_INSTALL" = "1" ]; then
  install_args+=("--force")
fi

info "installing mem9 via hermes plugins install"
HERMES_HOME="$HERMES_HOME" hermes plugins install "$PLUGIN_REPO" "${install_args[@]}"

[ -f "$PLUGIN_DIR/__init__.py" ] || fail "installed plugin is missing __init__.py"
[ -f "$PLUGIN_DIR/plugin.yaml" ] || fail "installed plugin is missing plugin.yaml"

hermes_project_root="$(detect_hermes_project_root)" || fail "unable to locate the Hermes repo; check HERMES_HOME or Hermes installation"
hermes_python="$(get_hermes_python "$hermes_project_root")"
info "using HERMES_HOME=$HERMES_HOME"
info "using Hermes project root $hermes_project_root"

existing_api_url_env="$(read_env_value "MEM9_API_URL" "$HERMES_ENV_FILE")"
existing_api_url_file="$(read_json_value "api_url" "$MEM9_CONFIG_FILE" "$hermes_python")"
existing_api_url="${existing_api_url_env:-$existing_api_url_file}"
if [ -z "$MEM9_API_URL" ]; then
  MEM9_API_URL="${existing_api_url:-$DEFAULT_API_URL}"
fi

existing_agent_id_env="$(read_env_value "MEM9_AGENT_ID" "$HERMES_ENV_FILE")"
existing_agent_id_file="$(read_json_value "agent_id" "$MEM9_CONFIG_FILE" "$hermes_python")"
existing_agent_id="${existing_agent_id_env:-$existing_agent_id_file}"
if [ -z "$MEM9_AGENT_ID" ]; then
  MEM9_AGENT_ID="${existing_agent_id:-$DEFAULT_AGENT_ID}"
fi

api_key="${MEM9_API_KEY:-}"
if [ -z "$api_key" ]; then
  api_key="$(read_env_value "MEM9_API_KEY" "$HERMES_ENV_FILE")"
fi

api_verified=1
api_is_new=0
if [ -n "$api_key" ]; then
  success "found existing MEM9_API_KEY — keeping it"
  if ! verify_api_key "$api_key" "$MEM9_API_URL"; then
    warn "existing API key failed connectivity check (network issue or wrong MEM9_API_URL?)"
    warn "keeping existing key — skipping activation"
    api_verified=0
  fi
else
  api_key="$(create_api_key)"
  api_is_new=1
  success "created a new MEM9_API_KEY"
fi

upsert_env_value "MEM9_API_KEY" "$api_key" "$HERMES_ENV_FILE"
if [ "$api_is_new" = "1" ]; then
  success "saved MEM9_API_KEY to $HERMES_ENV_FILE"
else
  success "MEM9_API_KEY unchanged in $HERMES_ENV_FILE"
fi

write_provider_config "$hermes_python"
if [ -f "$MEM9_CONFIG_FILE" ] && [ "$api_is_new" = "0" ]; then
  success "mem9 config up to date in $MEM9_CONFIG_FILE"
else
  success "saved mem9 config to $MEM9_CONFIG_FILE"
fi

ensure_memory_symlink "$hermes_project_root"

if [ "$api_verified" = "1" ]; then
  if ! activate_provider "$hermes_project_root" "$hermes_python"; then
    cleanup_memory_symlink "$hermes_project_root"
    fail "unable to activate memory.provider=$PLUGIN_NAME"
  fi
  printf '\n'
  success "mem9 is ready"
  printf 'Next: start a new Hermes session and run `hermes memory status` if you want to verify activation.\n'
else
  printf '\n'
  warn "mem9 is installed but NOT activated (API key could not be verified)"
  printf 'Next: fix the connectivity issue, then run `hermes memory setup` to complete activation.\n'
fi
