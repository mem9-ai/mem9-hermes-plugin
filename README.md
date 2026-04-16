# mem9 Hermes Plugin

Persistent cross-session memory for [Hermes Agent](https://github.com/NousResearch/hermes-agent), powered by [mem9](https://mem9.ai).

Conversations are automatically extracted into facts, recalled semantically each turn, and available across sessions and agents.

## Prerequisites

- Hermes Agent installed and working (`hermes version` should print version info)
- An internet connection (the plugin talks to the mem9 REST API)

## Quick Install

Review the script first if you prefer, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/mem9-ai/mem9-hermes-plugin/main/install.sh | bash
```

This single command:

1. Installs the plugin via `hermes plugins install`
2. Creates a symlink at `plugins/memory/mem9` inside the Hermes repo
3. Obtains an API key — reuses an existing `MEM9_API_KEY` (with a connectivity check), or creates a new one if none exists
4. Saves credentials to `HERMES_HOME/.env` and config to `mem9.json`
5. Activates `memory.provider=mem9` (skipped if the connectivity check failed)

If activation succeeds, start a new Hermes session — mem9 is active. If the script reports a connectivity failure, run `hermes memory setup` to reconfigure.

## Manual Install

```bash
# 1. Install the plugin files
hermes plugins install mem9-ai/mem9-hermes-plugin

# 2. Link into the Hermes memory provider directory
bash "${HERMES_HOME:-$HOME/.hermes}/plugins/mem9/scripts/link-memory-provider.sh"

# 3. Run the interactive setup (API key + activation)
hermes memory setup        # select "mem9" in the picker
```

During `hermes memory setup` you can auto-provision a free API key or enter an existing one. The setup flow tests the connection before saving.

## Verify

```bash
hermes memory status
```

You should see `mem9` listed as the active memory provider.

## Configuration

All files live under `${HERMES_HOME:-$HOME/.hermes}/`.

**`.env`** — credentials and optional overrides (env vars take precedence over `mem9.json`):

| Variable | Description |
|----------|-------------|
| `MEM9_API_KEY` | API key (required; also doubles as tenant ID) |
| `MEM9_API_URL` | Server URL override (default: `https://api.mem9.ai`) |
| `MEM9_AGENT_ID` | Agent identifier override (default: `hermes`) |

**`mem9.json`** — provider config:

| Key | Description |
|-----|-------------|
| `api_url` | Server URL (default: `https://api.mem9.ai`) |
| `agent_id` | Agent identifier (default: `hermes`) |
| `default_timeout_seconds` | General request timeout (default: 8) |
| `search_timeout_seconds` | Search/recall timeout (default: 15) |

## Uninstall

```bash
# Remove the symlink and plugin files
rm -f "$(hermes version 2>/dev/null | awk '/Project:/{print $2}')/plugins/memory/mem9"
hermes plugins remove mem9

# Switch to another provider or disable memory
hermes config set memory.provider ""
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `hermes memory status` doesn't show mem9 | Run `link-memory-provider.sh` — the symlink may be missing |
| "mem9 is not configured" during chat | Check that `MEM9_API_KEY` is set in `HERMES_HOME/.env` |
| Memories not appearing | Wait one turn — recall is prefetched asynchronously after the first turn |
| Connection errors | Verify `MEM9_API_URL` and check `HERMES_HOME/logs/agent.log` with `logging.level: DEBUG` in `config.yaml` |
