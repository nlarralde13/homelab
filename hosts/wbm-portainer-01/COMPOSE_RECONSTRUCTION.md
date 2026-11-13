# Portainer 1 Compose reconstruction

These Compose definitions are reconstructed from live Docker metadata because
the original Portainer-managed source files are not available as ordinary
files on `.30`.

They capture the current image, ports, restart policy, environment variable
names, and host mounts for Caddy, Homepage, Uptime Kuma, UniFi, and Portainer.
Homepage values are runtime placeholders by design; no credentials are stored
in Git.

The existing Prometheus stack remains the authoritative source for the
monitoring Compose project. Runtime databases and application data remain in
the NAS backup workflow.

Do not use these files for redeployment without comparing them to the current
Portainer stack and taking a fresh runtime backup.
