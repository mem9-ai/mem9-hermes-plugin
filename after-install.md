# Finish mem9 Setup

`hermes plugins install` has placed the plugin files into your Hermes plugin directory, but Hermes discovers memory providers from a separate path (`plugins/memory/` inside the Hermes repo). Two more steps are needed:

## 1. Create the symlink

```bash
bash "${HERMES_HOME:-$HOME/.hermes}/plugins/mem9/scripts/link-memory-provider.sh"
```

Expected output:

```
-> using HERMES_HOME=~/.hermes
-> using Hermes project root /path/to/hermes-agent
OK linked mem9 into /path/to/hermes-agent/plugins/memory/mem9
```

If the script cannot find your Hermes repo, set `HERMES_PROJECT_ROOT` explicitly:

```bash
HERMES_PROJECT_ROOT=/path/to/hermes-agent \
  bash "${HERMES_HOME:-$HOME/.hermes}/plugins/mem9/scripts/link-memory-provider.sh"
```

## 2. Run the interactive setup

```bash
hermes memory setup
```

- Select **mem9** in the picker
- Choose auto-provision (recommended) or enter an existing API key
- The setup tests your connection before saving

After successful setup:

```bash
hermes memory status   # should show mem9 as active
```

Start a new Hermes session and mem9 will begin capturing and recalling memories.
