#!/bin/bash
set +x
. "$(dirname -- "$0")/../scripts/quiet-common.sh"
q_start "$@"
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
    q_run "$Q_ROOT/scripts/status.sh" --state "$Q_STATE" --section compute || q_failed
    grep -q '^QUIET_CLASS=INSTANCE_PENDING$' "$Q_ATTEMPT" || q_failed
  elif grep -q '^BLOCKED: SSH_BOOTSTRAP_PENDING_OR_CHECK_FAILED$' "$Q_ATTEMPT" && grep -q '^QUIET_CLASS=READINESS$' "$Q_ATTEMPT"; then :
  else q_failed; fi
  if [ "$n" -lt 24 ]; then
    sleep 10
  fi
done
q_error '서버 준비 대기 시간이 끝났습니다. 대상은 보존했습니다. 상태 확인 또는 삭제가 필요합니다.'
