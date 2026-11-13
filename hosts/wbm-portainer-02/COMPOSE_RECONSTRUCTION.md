# Portainer 2 Compose reconstruction

The `media-apps` and `download-vpn` definitions are reconstructed from the
live `.40` container inventory and the preserved workspace source at
`wbm-portainer-02-pvr/compose`.

The live metadata agrees on the important recovery properties: service names,
images, host ports, media/config mounts, and the SABnzbd/Deluge/Moushole
network namespace relationship through Gluetun. The original Portainer stack
files are no longer present at their labeled `/data/compose` paths, so these
files must be reviewed before using them for a redeploy.

Known drift to resolve before redeploy:

- Live Gluetun reports the Docker network `wbm-pirateship-01_default`; the
  reconstructed file names its network `wbm-download-vpn`.
- Some live containers have no Compose project labels, while others retain
  stale service labels. Container labels are inventory evidence, not source of
  truth.
- Runtime application configuration remains on the host and in the NAS
  backup; it is not copied into Git because it contains service credentials
  and databases.

Do not run `docker compose up` from these files as part of collection. Any
redeploy requires a separate approved change with a backup and rollback plan.
