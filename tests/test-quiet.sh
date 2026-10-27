#!/bin/bash
# Wrapper integration against isolated fake lifecycle commands; no network or real runtime.
set -eu
SRC=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP=$(mktemp -d); TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/sync"
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/sleep"
printf '#!/bin/bash\nexit 97\n' > "$TMP/bin/aws"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" B6_EXPECTED_ACCOUNT=000000000001 B6_IAM_USER=fixture-user
export FAKE_LOG="$TMP/calls" FAKE_MODE=good
: > "$FAKE_LOG"
new() {
 R="$TMP/$1"; mkdir -p "$R/scripts" "$R/excute"; cp "$SRC/excute/install_aws.sh" "$SRC/excute/clean_aws.sh" "$R/excute/"; cp "$SRC/scripts/quiet-common.sh" "$R/scripts/"
 git -C "$R" init -q; printf 'runtime/\n' > "$R/.gitignore"
 cat > "$R/scripts/create.sh" <<'FAKE'
#!/bin/bash
set -u
run= state= apply=false
while [ "$#" -gt 0 ]; do case "$1" in --run-id) run=$2;shift 2;; --state) state=$2;shift 2;; --apply) apply=true;shift;; *) exit 90;; esac; done
printf 'create %s %s %s\n' "$apply" "$run" "$state" >> "$FAKE_LOG"
if ! $apply; then [ "${FAKE_MODE:-}" != planfail ] || exit 2; exit 0; fi
[ -f "$(dirname "$state")/quiet-aws/target" ] || exit 91
[ "$(cat "$(dirname "$state")/quiet-aws/target")" = "$run" ] || exit 92
if [ "${FAKE_MODE:-}" = long ]; then /bin/sleep 30; fi
(set -C; printf '{"schema":1,"run_id":"%s","status":"ACTIVE","refs":{}}\n' "$run" > "$state") || exit 93
chmod 600 "$state"
case "${FAKE_MODE:-}" in partial) printf '{"schema":1,"run_id":"%s","status":"WORKING","refs":{"vpc":"vpc-00000001"}}\n' "$run" > "$state"; printf 'BLOCKED: DRY_RUN_NOT_AUTHORIZED\n'; exit 1;; unknown) printf '{"status":"UNKNOWN","pending":"create-vpc","refs":{}}\n' > "$state";exit 1;; paused) printf '{"status":"WORKING","capture_waiting":true,"refs":{}}\n' > "$state";exit 1;; esac
FAKE
 cat > "$R/scripts/verify.sh" <<'FAKE'
#!/bin/bash
set -u
state=$2; f="${state}.attempt"; n=0; [ ! -e "$f" ] || n=$(cat "$f");n=$((n+1)); printf '%s' "$n" > "$f"
printf 'verify\n' >> "$FAKE_LOG"
case "${FAKE_MODE:-}" in
 progress) if [ "$n" -le 30 ]; then printf 'BOOTSTRAP_STATE=PACKAGES progress=%s-123\nBLOCKED: BOOTSTRAP_IN_PROGRESS\n' "$n";exit 1;fi;;
 stall) printf 'BOOTSTRAP_STATE=PACKAGES progress=10-123\nBLOCKED: BOOTSTRAP_IN_PROGRESS\n';exit 1;;
 fatal|oom|unavailable) case "$FAKE_MODE" in fatal) c=FAILED;;oom)c=OOM;;*)c=STATUS_UNAVAILABLE;;esac;printf 'BLOCKED: BOOTSTRAP_%s\n' "$c";exit 1;;
 transient) if [ "$n" = 1 ]; then printf 'PENDING: bootstrap/container not healthy\nBLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED\n';exit 1;fi;;
 timeout) printf 'Connection refused\nBLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED\n';exit 1;;
 hung) /bin/sleep 30;exit 1;;
 generic) printf 'BLOCKED: NON_AUTH_FAILURE\n';exit 1;;
 auth) printf 'BLOCKED: AWS_ERROR_ExpiredToken_NOT_ABSENCE\n';exit 1;;
 security) printf 'Permission denied (publickey).\nBLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED\n';exit 1;;
 pending|race|stopped) if [ "${FAKE_MODE:-}" = race ] && [ "$n" -gt 1 ]; then :; else printf 'BLOCKED: INSTANCE_NOT_RUNNING\n';exit 1;fi;;
esac
printf 'UNEXPECTED_RAW_CREDENTIAL_MUST_NOT_RETAIN\ncontainer_health=healthy\nlocalhost_root_http=200\n'
FAKE
 cat > "$R/scripts/status.sh" <<'FAKE'
#!/bin/bash
printf 'status\n' >> "$FAKE_LOG"
[ "${FAKE_MODE:-}" != race ] || { printf 'EC2 fixture state=running\n';exit 0; }
[ "${FAKE_MODE:-}" != stopped ] || { printf 'EC2 fixture state=stopped\n';exit 0; }
printf 'EC2 fixture state=pending\n'
FAKE
 cat > "$R/scripts/destroy.sh" <<'FAKE'
#!/bin/bash
state=$2
printf 'destroy %s\n' "$state" >> "$FAKE_LOG"
jq '.status="DESTROYED"' "$state" > "$state.tmp";mv "$state.tmp" "$state";chmod 600 "$state"
printf 'CLEANED exact_run=fixture\n'
FAKE
 cat > "$R/scripts/common.sh" <<'FAKE'
#!/bin/bash
# Fake AWS boundary only; exercises the actual wrapper read-only function.
parse() { STATE=$2; }
identity() { printf 'identity-read\n' >> "$FAKE_LOG"; }
load_state() { printf 'state-guard-read\n' >> "$FAKE_LOG"; }
sget() { jq -r "$1 // empty" "$STATE"; }
fail() { printf 'BLOCKED: %s\n' "$1"; exit 1; }
resource() {
  printf 'resource-guard-read\n' >> "$FAKE_LOG"
  PRESENT=true
  case "${FAKE_MODE:-}" in race) OBJ='{"State":{"Name":"running"}}';; stopped) OBJ='{"State":{"Name":"stopped"}}';; *) OBJ='{"State":{"Name":"pending"}}';; esac
}
FAKE
 chmod +x "$R/scripts/"*.sh
}
run() { set +e; (cd /; "$R/excute/$1" "${@:2}") > "$TMP/out" 2> "$TMP/err"; RC=$?; set -e; }
pass() { printf 'PASS %s\n' "$1"; }
new good; run install_aws.sh; [ "$RC" = 0 ]; [ "$(tail -1 "$TMP/out")" = '설치 완료' ]; [ ! -s "$TMP/err" ]; ! rg 'UNEXPECTED_RAW' "$R/runtime" >/dev/null
[ "$(stat -f %Lp "$R/runtime/quiet-aws/target" 2>/dev/null || stat -c %a "$R/runtime/quiet-aws/target")" = 600 ]
[ "$(stat -f %Lp "$R/runtime/quiet-aws" 2>/dev/null || stat -c %a "$R/runtime/quiet-aws")" = 700 ]; pass 'cwd-independent plan/apply/verify and exact quiet output/private target/log filtering'
run install_aws.sh; [ "$RC" != 0 ]; ! grep -q '설치 완료' "$TMP/out"; pass 'duplicate install refuses clobber'
run clean_aws.sh; [ "$RC" = 0 ]; [ "$(cat "$TMP/out")" = '삭제 완료' ]; run clean_aws.sh; [ "$RC" = 0 ]; pass 'clean exact target and repeated absence safe'; run install_aws.sh;[ "$RC" = 0 ];pass 'install-clean-install creates a new owned target and archives prior logs'
new absent; run clean_aws.sh; [ "$RC" = 0 ]; [ "$(cat "$TMP/out")" = '삭제 완료' ]; pass 'no wrapper-owned target clean is no-op'
new partial; export FAKE_MODE=partial; run install_aws.sh; [ "$RC" != 0 ]; ! grep -q '설치 완료' "$TMP/out"; target=$(cat "$R/runtime/quiet-aws/target"); [ -f "$R/runtime/$target-state.json" ]; export FAKE_MODE=good; run clean_aws.sh; [ "$RC" = 0 ]; grep -q "destroy $R/runtime/$target-state.json" "$FAKE_LOG"; pass 'known partial failure retains exact cleanup target'
for mode in unknown paused; do new "$mode";export FAKE_MODE=$mode;run install_aws.sh;[ "$RC" != 0 ];before=$(grep -c '^destroy' "$FAKE_LOG");run clean_aws.sh;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";[ "$(grep -c '^destroy' "$FAKE_LOG")" = "$before" ];done;pass 'UNKNOWN/pending capture markers block cleanup without clearing'
new transient;export FAKE_MODE=transient;run install_aws.sh;[ "$RC" = 0 ];[ "$(cat "$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json.attempt")" = 2 ];pass 'specific bootstrap readiness retries to verified success'
for mode in auth security stopped timeout pending;do new "$mode";sed 's/Q_MAX_ATTEMPTS=120/Q_MAX_ATTEMPTS=3/' "$R/excute/install_aws.sh" > "$R/excute/tmp";mv "$R/excute/tmp" "$R/excute/install_aws.sh";chmod +x "$R/excute/install_aws.sh";export FAKE_MODE=$mode;run install_aws.sh;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";n=$(cat "$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json.attempt");if [ "$mode" = timeout ] || [ "$mode" = pending ];then [ "$n" = 3 ];else [ "$n" = 1 ];fi;done;pass 'bounded wait; auth/security/stopped fail immediately without success'

new race;export FAKE_MODE=race;run install_aws.sh;[ "$RC" = 0 ];pass 'pending verifier followed by running status retries successfully'
sed 's/Q_MAX_ATTEMPTS=120/Q_MAX_ATTEMPTS=3/' "$R/excute/install_aws.sh" > "$R/excute/tmp";mv "$R/excute/tmp" "$R/excute/install_aws.sh";chmod +x "$R/excute/install_aws.sh"
before=$(grep -c '^create' "$FAKE_LOG");run install_aws.sh --verify-only;[ "$RC" = 0 ];[ "$(grep -c '^create' "$FAKE_LOG")" = "$before" ];pass 'ACTIVE verification-only performs zero create or apply calls'
for mode in auth security generic timeout;do export FAKE_MODE=$mode;run install_aws.sh --verify-only;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";[ -s "$TMP/err" ];[ "$(grep -c '^create' "$FAKE_LOG")" = "$before" ];done;pass 'verification-only errors/timeouts never mutate or report success'
export FAKE_MODE=good
state="$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json"
for patch in '.status="UNKNOWN"' '.pending="create-instance"' '.capture_waiting=true' '.run_id="wrong"' '.status="WORKING"';do cp "$state" "$TMP/restore";jq "$patch" "$state" > "$state.tmp";mv "$state.tmp" "$state";chmod 600 "$state";run install_aws.sh --verify-only;[ "$RC" != 0 ];[ -s "$TMP/err" ];cp "$TMP/restore" "$state";done
mkdir "$R/runtime/.quiet-aws.lock";run install_aws.sh --verify-only;[ "$RC" != 0 ];rmdir "$R/runtime/.quiet-aws.lock"
[ "$(grep -c '^create' "$FAKE_LOG")" = "$before" ];pass 'verification-only rejects unsafe operation state, wrong binding and lock'

new progress;export FAKE_MODE=progress;run install_aws.sh;[ "$RC" = 0 ];[ "$(cat "$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json.attempt")" = 31 ];grep -q 'Docker 패키지 설치 중' "$TMP/out";pass 'observable package progress beyond24 polls reaches healthy verification'
for mode in fatal oom unavailable stall;do new "$mode";export FAKE_MODE=$mode;if [ "$mode" = stall ];then sed 's/Q_STALL_SECONDS=600/Q_STALL_SECONDS=0/' "$R/excute/install_aws.sh" > "$R/excute/tmp";mv "$R/excute/tmp" "$R/excute/install_aws.sh";chmod +x "$R/excute/install_aws.sh";fi;run install_aws.sh;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";[ -s "$TMP/err" ];done;pass 'fatal package/cloud-init,OOM,unavailable status and stalled progress stop without false success'
new symlink;ln -s "$TMP" "$R/runtime";export FAKE_MODE=good;run install_aws.sh;[ "$RC" != 0 ];pass 'symlink runtime rejected before engine calls'
new targetlink;mkdir -m 700 "$R/runtime";ln -s "$TMP" "$R/runtime/quiet-aws";run clean_aws.sh;[ "$RC" != 0 ];pass 'symlink target rejected'
new noenv;unset B6_EXPECTED_ACCOUNT B6_IAM_USER;run install_aws.sh;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";[ ! -e "$R/runtime/quiet-aws" ] && [ ! -e "$R/runtime/.quiet-aws.lock" ];pass 'non-TTY missing identity fails before target/lock, never asks for credentials'
export B6_EXPECTED_ACCOUNT=000000000001 B6_IAM_USER=fixture-user FAKE_MODE=planfail
new planfail;run install_aws.sh;[ "$RC" != 0 ];run clean_aws.sh;[ "$RC" = 0 ];export FAKE_MODE=good;run install_aws.sh;[ "$RC" = 0 ];pass 'failed read-only plan can be archived without claiming a cloud delete'
state="$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json";jq '.run_id="wrong-target"' "$state" > "$state.tmp";mv "$state.tmp" "$state";chmod 600 "$state";run clean_aws.sh;[ "$RC" != 0 ];pass 'target and engine state run_id mismatch blocks cleanup'
export FAKE_MODE=long
new signal
"$R/excute/install_aws.sh" > "$TMP/first-out" 2> "$TMP/first-err" & PID=$!
for i in $(seq 1 100);do [ ! -e "$R/runtime/quiet-aws/phase-apply" ] || break;/bin/sleep .02;done
run install_aws.sh;[ "$RC" != 0 ];kill -TERM "$PID";set +e;wait "$PID";sigrc=$?;set -e;[ "$sigrc" != 0 ];[ ! -s "$TMP/first-out" ];[ -d "$R/runtime/.quiet-aws.lock" ];[ -f "$R/runtime/quiet-aws/target" ];pass 'concurrent run blocked; signal retains target/lock and never prints success'
new hung;export FAKE_MODE=hung
sed 's/Q_READ_LIMIT=120/Q_READ_LIMIT=1/' "$R/excute/install_aws.sh" > "$R/excute/install-new";mv "$R/excute/install-new" "$R/excute/install_aws.sh";chmod +x "$R/excute/install_aws.sh"
started=$SECONDS;run install_aws.sh;[ "$RC" != 0 ];! grep -q '설치 완료' "$TMP/out";[ "$((SECONDS-started))" -lt 8 ];pass 'one read-only verifier call has a bounded deadline'
# Exercise the unchanged real engine loader, not only permissive fake entry scripts.
new real-state;export FAKE_MODE=good;run install_aws.sh;[ "$RC" = 0 ]
state="$R/runtime/$(cat "$R/runtime/quiet-aws/target")-state.json"
cp "$SRC/scripts/common.sh" "$R/scripts/common.sh"
binding=$(printf 'fixture:%s' "$B6_EXPECTED_ACCOUNT" | shasum -a 256 | awk '{print $1}')
jq --arg run "$(cat "$R/runtime/quiet-aws/target")" --arg binding "$binding" --arg user "$B6_IAM_USER" '.+{schema:1,run_id:$run,region:"ap-northeast-2",profile:"b6-1-iam",account_salt:"fixture",account_binding:$binding,iam_user:$user,refs:{}}' "$state" > "$state.tmp";mv "$state.tmp" "$state";chmod 600 "$state"
( . "$R/scripts/common.sh"; STATE="$state"; load_state ) > "$TMP/loader-out" 2>&1
jq '.capture_waiting=true' "$state" > "$state.tmp";mv "$state.tmp" "$state";chmod 600 "$state"
if ( . "$R/scripts/common.sh"; STATE="$state"; load_state ) > "$TMP/loader-out" 2>&1;then exit 1;fi
grep -q CAPTURE_PAUSED_REQUIRES_REVIEW_NO_RERUN "$TMP/loader-out"
run clean_aws.sh;[ "$RC" != 0 ];pass 'real unchanged engine schema/binding and capture marker agree with wrapper guards'
# Run the actual remote bootstrap classifier with harmless command fixtures.
sed -n '/^IFS= read -r -d.*REMOTE_COMMAND/,/^REMOTE_COMMAND$/p' "$SRC/scripts/verify.sh" | sed '1d;$d' > "$TMP/remote-probe"
mkdir "$TMP/probe-bin"
cat > "$TMP/probe-bin/cloud-init" <<'FAKE'
#!/bin/bash
case "$PROBE" in error|oom) echo 'status: error';; unknown) echo 'status: unavailable';; *) echo 'status: running';; esac
FAKE
cat > "$TMP/probe-bin/sudo" <<'FAKE'
#!/bin/bash
shift
case "$1" in grep) [ "$PROBE" = package ];exit $?;; journalctl) [ "$PROBE" != oom ] || echo 'oom-kill';exit 0;; stat) [ "$PROBE" = metricsmissing ] && exit 1;echo 123-456;; *) exit 90;; esac
FAKE
printf '#!/bin/bash\nexit 0\n' > "$TMP/probe-bin/pgrep";chmod +x "$TMP/probe-bin/"*
for probe in running metricsmissing error package oom unknown;do set +e;PATH="$TMP/probe-bin:$PATH" PROBE=$probe bash "$TMP/remote-probe" > "$TMP/probe-out" 2> "$TMP/probe-err";code=$?;set -e;case "$probe" in running|metricsmissing) [ "$code" = 20 ];;error|package)[ "$code" = 21 ];;oom)[ "$code" = 22 ];;unknown)[ "$code" = 23 ];;esac;done
pass 'actual remote classifier handles running,missing metrics,cloud-init/package failure,OOM,unknown without services/network'
printf 'ALL QUIET WRAPPER CHECKS PASS (isolated fake lifecycle; no AWS/network)\n'
