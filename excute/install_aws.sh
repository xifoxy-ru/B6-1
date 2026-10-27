#!/bin/bash
set +x
. "$(dirname -- "$0")/../scripts/quiet-common.sh"
Q_VERIFY_ONLY=false
if [ "$#" = 1 ] && [ "$1" = --verify-only ]; then Q_VERIFY_ONLY=true; shift; fi
q_start "$@"
if $Q_VERIFY_ONLY; then
  q_target
  q_file "$Q_STATE"
  q_file "$Q_DIR/phase-apply"
  [ "$(cat "$Q_DIR/phase-apply")" = apply ] || q_error '기존 설치 실행 기록이 올바르지 않습니다.'
  q_blocked_state
  jq -e '.status=="ACTIVE"' "$Q_STATE" >/dev/null || q_error '기존 ACTIVE 설치 대상만 검증할 수 있습니다.'
  q_log verify-only; q_identity
else
[ ! -e "$Q_DIR" ] || q_error '기존 설치 대상이 있습니다. 삭제 도구 또는 상태 확인을 사용하세요. 덮어쓰지 않습니다.'
mkdir "$Q_DIR" || q_error '전용 대상 폴더를 만들 수 없습니다.'
Q_RUN="quiet-$(date -u +%Y%m%d%H%M%S)-$(LC_ALL=C od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
(set -C; printf '%s\n' "$Q_RUN" > "$Q_DIR/target") || q_error '설치 대상을 저장하지 못했습니다.'
sync || q_error '설치 대상 저장에 실패했습니다.'
q_target; q_log install; q_identity
q_mark plan
q_run "$Q_ROOT/scripts/create.sh" --run-id "$Q_RUN" --state "$Q_STATE" || q_failed
q_mark apply
q_run "$Q_ROOT/scripts/create.sh" --run-id "$Q_RUN" --state "$Q_STATE" --apply || q_failed
fi
q_blocked_state
# Each verifier is read-only apart from its dedicated SSH known_hosts file.
# A finite attempt count plus per-SSH/curl timeouts bounds readiness waiting.
Q_READ_LIMIT=120
Q_MAX_ATTEMPTS=120
Q_MAX_SECONDS=1800
Q_STALL_SECONDS=600
started=$SECONDS
last_progress_at=$SECONDS
last_progress=
last_notice=
q_wait_budget() {
  remaining=$((Q_MAX_SECONDS-(SECONDS-started)))
  [ "$remaining" -gt 0 ] || q_error '서버 준비 대기 30분이 끝났습니다. 대상은 보존했습니다.'
  Q_READ_LIMIT=$remaining
  [ "$Q_READ_LIMIT" -le 120 ] || Q_READ_LIMIT=120
}
n=0
while [ "$n" -lt "$Q_MAX_ATTEMPTS" ] && [ "$((SECONDS-started))" -lt "$Q_MAX_SECONDS" ]; do
  n=$((n+1))
  q_wait_budget
  if q_run "$Q_ROOT/scripts/verify.sh" --state "$Q_STATE"; then
    printf '설치 완료\n'; exit 0
  fi
  q_blocked_state
  grep -q '^QUIET_CLASS=SECURITY$' "$Q_ATTEMPT" && q_failed
  if grep -q '^BLOCKED: INSTANCE_NOT_RUNNING$' "$Q_ATTEMPT"; then
    q_wait_budget
    q_run q_read_compute_state || q_failed
    grep -Eq '^QUIET_CLASS=INSTANCE_(PENDING|RUNNING)$' "$Q_ATTEMPT" || q_failed
  elif grep -q '^BLOCKED: BOOTSTRAP_IN_PROGRESS$' "$Q_ATTEMPT"; then
    progress=$(grep '^BOOTSTRAP_STATE=' "$Q_ATTEMPT" | tail -1)
    [ -n "$progress" ] || q_failed
    if [ "$progress" != "$last_progress" ]; then last_progress=$progress; last_progress_at=$SECONDS; fi
    [ "$((SECONDS-last_progress_at))" -lt "$Q_STALL_SECONDS" ] || q_error '자동 설치 로그가 10분 동안 진행되지 않았습니다. 대상은 보존했으며 원인 확인이 필요합니다.'
    case "$progress" in BOOTSTRAP_STATE=PACKAGES*) notice='Docker 패키지 설치 중입니다.';; BOOTSTRAP_STATE=COMPOSE*) notice='Compose와 실행 설정을 준비 중입니다.';; BOOTSTRAP_STATE=IMAGES*) notice='이미지 내려받기·컨테이너 생성 중입니다.';; BOOTSTRAP_STATE=CONTAINER*) notice='컨테이너 상태를 확인 중입니다.';; *) notice='서버 자동 설치가 진행 중입니다.';; esac
    if [ "$notice" != "$last_notice" ]; then printf '%s\n' "$notice"; last_notice=$notice; fi
  elif grep -q '^BLOCKED: BOOTSTRAP_FAILED$' "$Q_ATTEMPT"; then q_error '서버 자동 설치가 실패했습니다. 재설치하지 말고 설치 기록을 확인하세요.'
  elif grep -q '^BLOCKED: BOOTSTRAP_OOM$' "$Q_ATTEMPT"; then q_error '서버 메모리 부족 종료 기록이 있습니다. 대상은 보존했습니다.'
  elif grep -q '^BLOCKED: BOOTSTRAP_STATUS_UNAVAILABLE$' "$Q_ATTEMPT"; then q_error '자동 설치 상태를 확인할 수 없습니다. 성공으로 처리하지 않습니다.'
  elif grep -Eq '^BLOCKED: (SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED|EXTERNAL_HTTP_FAILED|EXTERNAL_HEALTH_FAILED)$' "$Q_ATTEMPT" && grep -q '^QUIET_CLASS=CONNECTIVITY$' "$Q_ATTEMPT"; then
    if [ "$last_notice" != 연결 ]; then printf 'SSH·HTTP 연결을 기다립니다.\n'; last_notice=연결; fi
  elif grep -q '^BLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED$' "$Q_ATTEMPT" && grep -q '^QUIET_CLASS=READINESS$' "$Q_ATTEMPT"; then
    if [ "$last_notice" != '컨테이너·HTTP 서비스 준비를 기다립니다.' ]; then printf '컨테이너·HTTP 서비스 준비를 기다립니다.\n'; last_notice='컨테이너·HTTP 서비스 준비를 기다립니다.'; fi
  else q_failed; fi
  if [ "$n" -lt "$Q_MAX_ATTEMPTS" ]; then
    remaining=$((Q_MAX_SECONDS-(SECONDS-started)))
    if [ "$remaining" -gt 0 ]; then if [ "$remaining" -lt 10 ]; then sleep "$remaining"; else sleep 10; fi; fi
  fi
done
q_error '서버 준비 대기 한도(최대 30분 또는 120회)가 끝났습니다. 대상은 보존했습니다. 상태 확인 또는 삭제가 필요합니다.'
