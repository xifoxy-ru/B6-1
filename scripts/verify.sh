#!/bin/bash
set +x
. "$(dirname -- "$0")/common.sh"
parse "$@"; identity; load_state
[ "$(sget '.status')" = ACTIVE ] || fail ACTIVE_STATE_REQUIRED_NO_OLD_ENDPOINT
resource instance; $PRESENT || fail INSTANCE_ABSENT
[ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" = running ] || fail INSTANCE_NOT_RUNNING
SERVER=$(printf '%s' "$OBJ" | jq -r '.PublicIpAddress // empty'); [ -n "$SERVER" ] || fail NO_PUBLIC_SERVER_IP
KEY_PATH=$(sget '.key_path'); check_path "$KEY_PATH"; case "$KEY_PATH" in "$ROOT/.secrets/"*) ;; *) fail PRIVATE_PATH_SCOPE;; esac; [ -O "$KEY_PATH" ] && [ "$(mode "$(dirname -- "$KEY_PATH")")" = 700 ] || fail PRIVATE_OWNER_DIRECTORY; [ -f "$KEY_PATH" ] && [ "$(mode "$KEY_PATH")" = 600 ] || fail PRIVATE_KEY_MODE
printf '\n=== REAL SSH / DOCKER / LOCAL HTTP / OUTBOUND ===\n'
IFS= read -r -d '' REMOTE <<'REMOTE_COMMAND' || :
set -eu
# Inspect first-boot status before treating a missing application as a failure.
log=/var/log/b6-1-bootstrap.log
ci=$(cloud-init status 2>/dev/null) || ci_rc=$?
failed=false
sudo -n grep -q 'B6-1 BOOTSTRAP FAILED' "$log" 2>/dev/null && failed=true
case "$ci" in *'status: error'*|*'status: degraded'*) failed=true;; esac
if $failed; then
  if sudo -n journalctl -k -b --no-pager 2>/dev/null | grep -Eqi 'Out of memory|oom-kill|Killed process.*oom'; then
    printf 'BOOTSTRAP_STATE=OOM\n'; exit 22
  fi
  printf 'BOOTSTRAP_STATE=FAILED\n'; exit 21
fi
case "$ci" in
  *'status: running'*)
    phase=STARTING
    if pgrep -x dnf >/dev/null 2>&1; then phase=PACKAGES
    elif [ ! -x /usr/local/lib/docker/cli-plugins/docker-compose ]; then phase=COMPOSE
    elif sudo -n grep -qE 'Container.*Started' "$log" 2>/dev/null; then phase=CONTAINER
    elif [ -f /opt/b6-1/compose.yaml ]; then phase=IMAGES
    fi
    progress=$(sudo -n stat -c '%s-%Y' "$log" 2>/dev/null || printf unavailable)
    printf 'BOOTSTRAP_STATE=%s progress=%s\n' "$phase" "$progress"
    exit 20;;
  *'status: done'*) ;;
  *) printf 'BOOTSTRAP_STATE=STATUS_UNAVAILABLE\n'; exit 23;;
esac
cd /opt/b6-1
sudo -n docker version --format 'Docker server={{.Server.Version}}'
sudo -n docker compose version
sudo -n docker compose config --quiet
sudo -n docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
health=$(sudo -n docker inspect b6-1-web-1 --format '{{.State.Health.Status}}')
printf 'container_health=%s\n' "$health"
[ "$health" = healthy ] || { printf 'PENDING: bootstrap/container not healthy\n'; exit 3; }
code=$(curl --max-time 15 --fail --silent --show-error -o /dev/null -w '%{http_code}' http://127.0.0.1/)
printf 'localhost_root_http=%s\n' "$code"; [ "$code" = 200 ]
code=$(curl --max-time 15 --fail --silent --show-error -o /dev/null -w '%{http_code}' http://127.0.0.1/health)
printf 'localhost_health_http=%s\n' "$code"; [ "$code" = 200 ]
body=$(curl --max-time 15 --fail --silent http://127.0.0.1/health)
[ "$body" = 'B6-1 OK' ]; printf 'localhost_health_body=B6-1 OK\n'
code=$(curl --max-time 15 --fail --silent --show-error -o /dev/null -w '%{http_code}' https://example.com)
printf 'outbound_tls_http=%s\n' "$code"; [ "$code" = 200 ]
printf 'served_file_sha256='; sha256sum /opt/b6-1/app/index.html
REMOTE_COMMAND
ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$ROOT/runtime/$RUN_ID-known_hosts" -i "$KEY_PATH" "ec2-user@$SERVER" "$REMOTE"
ssh_rc=$?
case "$ssh_rc" in
  0) ;;
  20) fail BOOTSTRAP_IN_PROGRESS;;
  21) fail BOOTSTRAP_FAILED;;
  22) fail BOOTSTRAP_OOM;;
  23) fail BOOTSTRAP_STATUS_UNAVAILABLE;;
  *) fail SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED;;
esac
printf '\n=== EXTERNAL HTTP (actual requests) ===\n'
code=$(curl --fail --silent --show-error --noproxy '*' --max-time 15 -o /dev/null -w '%{http_code}' "http://$SERVER/") || fail EXTERNAL_HTTP_FAILED
[ "$code" = 200 ] || fail EXTERNAL_ROOT_NOT_200
remote_hash=$(curl --fail --silent --show-error --noproxy '*' --max-time 15 "http://$SERVER/" | sha)
[ "$remote_hash" = "$(sha < "$ROOT/app/index.html")" ] || fail EXTERNAL_SOURCE_MISMATCH
code=$(curl --max-time 15 --fail --silent --show-error --noproxy '*' -o /dev/null -w '%{http_code}' "http://$SERVER/health") || fail EXTERNAL_HEALTH_FAILED
[ "$code" = 200 ] || fail EXTERNAL_HEALTH_NOT_200
health=$(curl --fail --silent --show-error --noproxy '*' --max-time 15 "http://$SERVER/health") || fail EXTERNAL_HEALTH_FAILED
[ "$health" = 'B6-1 OK' ] || fail EXTERNAL_HEALTH_MISMATCH
printf 'external_root_http=200 source_sha256=%s MATCH\nexternal_health_http=200 body=B6-1 OK\nURL=http://%s/\n' "$remote_hash" "$SERVER"
