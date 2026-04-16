# mem9 Plugin — Post-Install Steps

> **Used `install.sh`?** Everything below is already done — no action needed.
> The steps below are only for manual `hermes plugins install` users.

---

`hermes plugins install` places the plugin files into your Hermes plugin directory,
but Hermes discovers memory providers from a separate path (`plugins/memory/`
inside the Hermes repo). Two more steps are needed:

## 1. Create the symlink

```bash
bash "${HERMES_HOME:-$HOME/.hermes}/plugins/mem9/scripts/link-memory-provider.sh"
```

If the script cannot find your Hermes repo, set `HERMES_PROJECT_ROOT`:

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

## Verify

```bash
hermes memory status   # should show mem9 as active
```
