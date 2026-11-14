#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
readonly REPO_DIR="/home/cogscontrol/homelab"
readonly WORK_DIR="$(mktemp -d /tmp/homelab-config.XXXXXX)"
readonly WEBHOOK_ENV="/home/cogscontrol/.config/cerebro-bridge/bridge.env"
readonly DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly COMMIT_NAME="Cerebro Configuration Backup"
readonly COMMIT_EMAIL="cerebro-backup@localhost"

cleanup() { rm -rf -- "${WORK_DIR}"; }
trap cleanup EXIT

notify() {
  local message="$1" payload
  [ -r "${WEBHOOK_ENV}" ] || return 0
  set +u
  set -a
  # shellcheck disable=SC1090
  . "${WEBHOOK_ENV}"
  set +a
  set -u
  [ -n "${CEREBRO_BRIDGE_DISCORD_WEBHOOK_URL:-}" ] || return 0
  payload="$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "${message}")"
  if curl -fsS --max-time 10 -H 'Content-Type: application/json' \
    -X POST -d "${payload}" "${CEREBRO_BRIDGE_DISCORD_WEBHOOK_URL}" \
    >/dev/null 2>/tmp/homelab-config-backup-discord.err; then
    echo "Discord backup notification accepted"
  else
    rc=$?
    echo "Discord backup notification failed (curl exit ${rc}): $(tr '\n' ' ' </tmp/homelab-config-backup-discord.err)" >&2
  fi
}

failed() {
  local rc=$?
  notify "❌ Homelab configuration backup failed on $(hostname -s) at ${DATE_UTC}. Check the Cerebro backup service logs."
  exit "${rc}"
}
trap failed ERR

mkdir -p "${WORK_DIR}/hosts/wbm-portainer-01/compose/prometheus-stack" \
  "${WORK_DIR}/hosts/wbm-portainer-01/config/blackbox" \
  "${WORK_DIR}/hosts/wbm-portainer-01/config/homepage" \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/crafty" \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/minecraft-paper-test" \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/media-apps" \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/download-vpn" \
  "${WORK_DIR}/inventory"

scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.30:/home/mediacontrol/prometheus-stack/compose.yml \
  "${WORK_DIR}/hosts/wbm-portainer-01/compose/prometheus-stack/compose.yml"
scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.30:/home/mediacontrol/prometheus-stack/prometheus.yml \
  "${WORK_DIR}/hosts/wbm-portainer-01/compose/prometheus-stack/prometheus.yml"
scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.30:/home/mediacontrol/prometheus-stack/alertmanager.yml \
  "${WORK_DIR}/hosts/wbm-portainer-01/compose/prometheus-stack/alertmanager.yml"
scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.30:/etc/docker/blackbox/blackbox.yml \
  "${WORK_DIR}/hosts/wbm-portainer-01/config/blackbox/blackbox.yml"

for file in bookmarks.yaml docker.yaml kubernetes.yaml proxmox.yaml services.yaml settings.yaml widgets.yaml; do
  scp -q -o BatchMode=yes -o ConnectTimeout=10 \
    "mediacontrol@192.168.1.30:/etc/docker/homepage/config/${file}" \
    "${WORK_DIR}/hosts/wbm-portainer-01/config/homepage/${file}"
done

scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.40:/home/mediacontrol/crafty/compose.yaml \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/crafty/compose.yaml"
scp -q -o BatchMode=yes -o ConnectTimeout=10 \
  mediacontrol@192.168.1.40:/home/mediacontrol/minecraft-paper-test/compose.yaml \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/minecraft-paper-test/compose.yaml"

# These two Portainer-managed stacks no longer retain their source files on
# .40. The workspace copy is the reviewed reconstruction from the live host;
# keep it under version control until the definitions can be exported directly
# from Portainer and reconciled.
cp -a /home/cogscontrol/wbm-portainer-02-pvr/compose/media-apps.compose.yml \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/media-apps/compose.yml"
cp -a /home/cogscontrol/wbm-portainer-02-pvr/compose/download-vpn.compose.yml \
  "${WORK_DIR}/hosts/wbm-portainer-02/compose/download-vpn/compose.yml"

# Runtime inventory contains names, images, Compose source paths, and mount
# paths only. Environment values are deliberately omitted.
ssh -o BatchMode=yes -o ConnectTimeout=15 mediacontrol@192.168.1.30 \
  'docker ps -a --format "{{.Names}}" | while read -r n; do docker inspect "$n" --format "{{.Name}}|{{.Config.Image}}|{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}|{{index .Config.Labels \"com.docker.compose.project.config_files\"}}|{{range .Mounts}}{{.Source}} -> {{.Destination}};{{end}}" 2>/dev/null; done | sort' \
  > "${WORK_DIR}/inventory/wbm-portainer-01.docker-manifest.raw"
ssh -o BatchMode=yes -o ConnectTimeout=15 mediacontrol@192.168.1.40 \
  'docker ps -a --format "{{.Names}}" | while read -r n; do docker inspect "$n" --format "{{.Name}}|{{.Config.Image}}|{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}|{{index .Config.Labels \"com.docker.compose.project.config_files\"}}|{{range .Mounts}}{{.Source}} -> {{.Destination}};{{end}}" 2>/dev/null; done | sort' \
  > "${WORK_DIR}/inventory/wbm-portainer-02.docker-manifest.raw"

python3 - "${WORK_DIR}/inventory" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for raw in root.glob("*.docker-manifest.raw"):
    output = raw.with_name(raw.name.replace(".raw", ""))
    lines = []
    for line in raw.read_text().splitlines():
        fields = line.split("|", 5)
        if len(fields) == 6:
            mounts = sorted(filter(None, fields[5].split(";")))
            fields[5] = ";".join(mounts) + (";" if mounts else "")
            line = "|".join(fields)
        lines.append(line)
    output.write_text("\n".join(sorted(lines)) + "\n")
    raw.unlink()
PY

cat > "${WORK_DIR}/inventory/collection-manifest.txt" <<EOF
collector_version=1
source_hosts=192.168.1.30,192.168.1.40
collector=$(hostname -s)
mode=read-only
secrets=excluded
runtime_databases=excluded
EOF

rm -f "${WORK_DIR}"/**/*.env "${WORK_DIR}"/**/*.secret 2>/dev/null || true
cp -a "${WORK_DIR}/." "${REPO_DIR}/"
cd "${REPO_DIR}"

possible_values="$(git grep -n -I -E '(password|api[_-]?key|token|secret)[[:space:]]*[:=][[:space:]]*[\"'\''`]?[A-Za-z0-9][A-Za-z0-9+/_=-]{15,}[\"'\''`]?[[:space:]]*$' -- . ':!scripts/collect-and-push.sh' || true)"
private_key_headers="$(git grep -n -I -E 'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' -- . ':!scripts/collect-and-push.sh' || true)"
if [ -n "${possible_values}${private_key_headers}" ]; then
  printf '%s\n%s\n' "${possible_values}" "${private_key_headers}" >&2
  echo "possible secret detected; refusing to commit" >&2
  exit 1
fi

git config user.name "${COMMIT_NAME}"
git config user.email "${COMMIT_EMAIL}"
git add --all
if git diff --cached --quiet; then
  git push origin main
  notify "✅ Homelab configuration backup completed on $(hostname -s) at ${DATE_UTC}; no configuration changes were detected."
  exit 0
fi

git commit -m "Backup homelab configuration ${DATE_UTC}"
git push origin main
notify "✅ Homelab configuration backup committed and pushed at ${DATE_UTC}."
