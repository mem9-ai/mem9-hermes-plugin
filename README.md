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

## Upgrade

```bash
hermes plugins update mem9
```

This runs `git pull` inside the installed plugin directory. Start a new Hermes session to pick up the changes. Your `.env` and `mem9.json` are not touched.

For installations created before credential-file hardening, also restrict the existing file:

```bash
chmod 600 "${HERMES_HOME:-$HOME/.hermes}/.env"
```

Updating the plugin does not rotate an existing key. If a key was exposed, contact
the operator of your mem9 service to disable the affected credential or Space;
creating a new Space alone does not revoke the old key.

If the symlink is missing after an upgrade (e.g. Hermes was reinstalled), re-run:

```bash
bash "${HERMES_HOME:-$HOME/.hermes}/plugins/mem9/scripts/link-memory-provider.sh"
```

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

## Security boundaries

An API key grants access to its Space's shared memories, including memories from
other sessions and agents using that key. `agent_id`, `session_id`, and
`X-Mnemo-Agent-Id` identify sources and callers; they are not authorization
boundaries. Use separate Spaces and keys for users or agents that must not share
access. Providers are initialized for one agent instance; reusing one initialized
provider across different identities is unsupported.

The model can call memory update and delete tools without a separate human
confirmation. Enable the plugin only for agents trusted to manage that Space.
The mem9 server soft-deletes memory records, but this plugin does not provide an
undo command or a complete audit trail. A self-hosted server controls its own
deletion and retention behavior.

Server URLs must use HTTPS, except HTTP on `localhost` or a loopback IP for local
development. Custom HTTPS endpoints remain supported: configure only a server
you trust with your API key and conversation content. The installer does not
follow redirects when provisioning or verifying a key.

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
| Memories not appearing | Check `hermes memory status` and `agent.log` for errors; recall runs every turn including the first |
| Connection errors | Verify `MEM9_API_URL` and check `HERMES_HOME/logs/agent.log` with `logging.level: DEBUG` in `config.yaml` |
