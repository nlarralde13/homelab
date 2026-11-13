# Collection policy

The collector is read-only against `.30` and `.40`. It collects only approved
Compose definitions and non-secret configuration. It does not copy application
databases, media, logs, metrics, or `.env` files into Git.

## Current sources

### `.30` / `wbm-portainer-01`

- `/home/mediacontrol/prometheus-stack/compose.yml`
- `/home/mediacontrol/prometheus-stack/prometheus.yml`
- `/home/mediacontrol/prometheus-stack/alertmanager.yml`
- `/etc/docker/blackbox/blackbox.yml`
- selected Homepage YAML configuration

### `.40` / `wbm-portainer-02`

- `/home/mediacontrol/crafty/compose.yaml`
- `/home/mediacontrol/minecraft-paper-test/compose.yaml`
- sanitized Docker runtime manifest and mounted configuration path inventory

Portainer-managed stacks whose original Compose files are not present as live
files are represented by the sanitized runtime manifest until their source
definitions are exported and reviewed. This avoids inventing configuration or
copying application secrets from runtime directories.

## Secret rule

Before every commit, the collector scans staged text for common credential
patterns and aborts if a likely secret is found. This is a guardrail, not a
replacement for review. Never add `.env`, API keys, passwords, private keys,
database files, or service tokens to this repository.
