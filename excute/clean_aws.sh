#!/bin/bash
set +x
. "$(dirname -- "$0")/../scripts/quiet-common.sh"
q_start "$@"
[ -e "$Q_DIR" ] || { printf '삭제 완료\n'; exit 0; }
q_target; q_log clean
if [ ! -e "$Q_STATE" ]; then
  [ ! -e "$Q_DIR/phase-apply" ] || q_error '생성 시도 후 상태 파일이 없습니다. 추측해서 삭제하지 않습니다. 수동 확인이 필요합니다.'
  q_archive
  printf '삭제 완료\n'; exit 0
fi
q_blocked_state; q_identity
q_run "$Q_ROOT/scripts/destroy.sh" --state "$Q_STATE" --apply || q_failed
q_file "$Q_STATE"
[ "$(jq -r '.status' "$Q_STATE")" = DESTROYED ] || q_error '삭제 완료 상태를 확인하지 못했습니다.'
q_archive
printf '삭제 완료\n'
