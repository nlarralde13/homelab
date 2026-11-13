# Homelab configuration record

This repository is the versioned configuration record for the homelab Docker
environments currently hosted on:

- `wbm-portainer-01` / `192.168.1.30`
- `wbm-portainer-02` / `192.168.1.40`

It stores Compose definitions, non-secret configuration, sanitized runtime
manifests, and collection metadata. Secrets, environment files, databases,
metrics, logs, and application runtime state remain outside Git in the NAS
backup workflow.

## Git flow

The scheduled collector runs from Cogs Control, gathers the approved live
configuration, rejects secret-bearing files, commits changed snapshots, pushes
to `origin/main`, and sends a Discord success/failure notification through the
existing Cerebro webhook configuration.

The collector is intentionally configuration-only. It does not redeploy,
restart, or mutate Docker workloads.

## Layout

```text
hosts/
  wbm-portainer-01/   # monitoring, proxy, dashboard, and host config
  wbm-portainer-02/   # media/download and game Compose definitions
inventory/             # sanitized live container and source-path metadata
scripts/               # collection and Git automation
```

See `docs/COLLECTION_POLICY.md` for the allowlist and exclusions.
