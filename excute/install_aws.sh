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
n=0
while [ "$n" -lt 24 ]; do
  n=$((n+1))
  if q_run "$Q_ROOT/scripts/verify.sh" --state "$Q_STATE"; then
    printf '설치 완료\n'; exit 0
  fi
  q_blocked_state
  grep -q '^QUIET_CLASS=SECURITY$' "$Q_ATTEMPT" && q_failed
  if grep -q '^BLOCKED: INSTANCE_NOT_RUNNING$' "$Q_ATTEMPT"; then
    q_run q_read_compute_state || q_failed
    grep -Eq '^QUIET_CLASS=INSTANCE_(PENDING|RUNNING)$' "$Q_ATTEMPT" || q_failed
  elif grep -q '^BLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED$' "$Q_ATTEMPT" && grep -q '^QUIET_CLASS=READINESS$' "$Q_ATTEMPT"; then :
  else q_failed; fi
  if [ "$n" -lt 24 ]; then
    sleep 10
  fi
done
q_error '서버 준비 대기 시간이 끝났습니다. 대상은 보존했습니다. 상태 확인 또는 삭제가 필요합니다.'
