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
REMOTE=$(cat <<'REMOTE_COMMAND'
set -eu
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
)
ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$ROOT/runtime/$RUN_ID-known_hosts" -i "$KEY_PATH" "ec2-user@$SERVER" "$REMOTE" || fail SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED
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
