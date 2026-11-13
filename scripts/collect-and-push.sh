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
  curl -fsS --max-time 10 -H 'Content-Type: application/json' \
    -X POST -d "${payload}" "${CEREBRO_BRIDGE_DISCORD_WEBHOOK_URL}" \
    >/dev/null 2>&1 || true
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

# Runtime inventory contains names, images, Compose source paths, and mount
# paths only. Environment values are deliberately omitted.
ssh -o BatchMode=yes -o ConnectTimeout=15 mediacontrol@192.168.1.30 \
  'docker ps -a --format "{{.Names}}" | while read -r n; do docker inspect "$n" --format "{{.Name}}|{{.Config.Image}}|{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}|{{index .Config.Labels \"com.docker.compose.project.config_files\"}}|{{range .Mounts}}{{.Source}} -> {{.Destination}};{{end}}" 2>/dev/null; done | sort' \
  > "${WORK_DIR}/inventory/wbm-portainer-01.docker-manifest.txt"
ssh -o BatchMode=yes -o ConnectTimeout=15 mediacontrol@192.168.1.40 \
  'docker ps -a --format "{{.Names}}" | while read -r n; do docker inspect "$n" --format "{{.Name}}|{{.Config.Image}}|{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}|{{index .Config.Labels \"com.docker.compose.project.config_files\"}}|{{range .Mounts}}{{.Source}} -> {{.Destination}};{{end}}" 2>/dev/null; done | sort' \
  > "${WORK_DIR}/inventory/wbm-portainer-02.docker-manifest.txt"

cat > "${WORK_DIR}/inventory/collection-manifest.txt" <<EOF
collected_at=${DATE_UTC}
source_hosts=192.168.1.30,192.168.1.40
collector=$(hostname -s)
mode=read-only
secrets=excluded
runtime_databases=excluded
EOF

rm -f "${WORK_DIR}"/**/*.env "${WORK_DIR}"/**/*.secret 2>/dev/null || true
cp -a "${WORK_DIR}/." "${REPO_DIR}/"
cd "${REPO_DIR}"

if git grep -n -I -E '(password[[:space:]]*[:=]|api[_-]?key[[:space:]]*[:=]|token[[:space:]]*[:=]|secret[[:space:]]*[:=]|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' -- . ':!scripts/collect-and-push.sh'; then
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
