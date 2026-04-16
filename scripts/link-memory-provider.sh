#!/usr/bin/env bash

set -euo pipefail

PLUGIN_NAME="mem9"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_PROJECT_HINT="${HERMES_PROJECT_ROOT:-}"

info() {
  printf -- '-> %s\n' "$*"
}

success() {
  printf 'OK %s\n' "$*"
}

fail() {
  printf 'ERROR %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
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

ensure_memory_symlink() {
  local hermes_project_root="$1"
  local memory_dir="$hermes_project_root/plugins/memory"
  local memory_link="$memory_dir/$PLUGIN_NAME"

  mkdir -p "$memory_dir"

  if [ -L "$memory_link" ]; then
    if [ "$(readlink "$memory_link")" = "$PLUGIN_ROOT" ]; then
      success "memory symlink already points at $PLUGIN_ROOT"
      return 0
    fi

    rm "$memory_link"
    ln -s "$PLUGIN_ROOT" "$memory_link"
    success "updated memory symlink at $memory_link"
    return 0
  fi

  if [ -e "$memory_link" ]; then
    fail "found an existing path at $memory_link; move it away before enabling mem9"
  fi

  ln -s "$PLUGIN_ROOT" "$memory_link"
  success "linked mem9 into $memory_link"
}

main() {
  local hermes_project_root=""

  [ -f "$PLUGIN_ROOT/__init__.py" ] || fail "expected plugin files in $PLUGIN_ROOT"
  [ -f "$PLUGIN_ROOT/plugin.yaml" ] || fail "expected plugin.yaml in $PLUGIN_ROOT"

  hermes_project_root="$(detect_hermes_project_root)" || fail "unable to locate the Hermes repo; check HERMES_HOME or Hermes installation"

  info "using HERMES_HOME=$HERMES_HOME"
  info "using Hermes project root $hermes_project_root"

  ensure_memory_symlink "$hermes_project_root"

  printf '\n'
  success "mem9 is discoverable by hermes memory setup"
  printf 'Next: run `hermes memory setup` and select mem9.\n'
}

main "$@"
