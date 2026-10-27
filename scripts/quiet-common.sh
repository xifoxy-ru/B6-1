#!/bin/bash
# Thin, offline-tested entry adapter. Existing lifecycle guards remain authoritative.
set +x
set +e
set -u
umask 077
Q_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 1
Q_DIR="$Q_ROOT/runtime/quiet-aws"
Q_LOCK="$Q_ROOT/runtime/.quiet-aws.lock"
Q_CHILD= Q_READER= Q_WATCH= Q_LOG= Q_LOCKED=false Q_SIGNAL=false Q_N=0
q_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
q_error() { printf '오류: %s' "$1" >&2; [ -z "$Q_LOG" ] || printf ' (기록: %s)' "$Q_LOG" >&2; printf '\n' >&2; exit 1; }
q_path() {
  local p=$1
  while [ "$p" != / ]; do [ ! -L "$p" ] || q_error '심볼릭 링크 경로는 사용할 수 없습니다.'; p=$(dirname -- "$p"); done
}
q_private_dir() { [ -d "$1" ] && [ -O "$1" ] && [ "$(q_mode "$1")" = 700 ] || q_error '전용 폴더 소유권·권한을 확인하세요.'; }
q_file() { q_path "$1"; [ -f "$1" ] && [ -O "$1" ] && [ "$(q_mode "$1")" = 600 ] || q_error '대상 기록 소유권·권한을 확인하세요.'; }
q_finish() {
  if $Q_LOCKED && ! $Q_SIGNAL; then rmdir "$Q_LOCK" 2>/dev/null || :; fi
}
q_stop_tree() {
  local pid=$1 parent=$2 child actual
  actual=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "$actual" = "$parent" ] || return 0
  for child in $(ps -axo pid=,ppid= 2>/dev/null | awk -v parent="$pid" '$2==parent {print $1}'); do q_stop_tree "$child" "$pid"; done
  kill -TERM "$pid" 2>/dev/null || :
}
q_signal() {
  Q_SIGNAL=true
  [ -z "$Q_WATCH" ] || { q_stop_tree "$Q_WATCH" "$$"; wait "$Q_WATCH" 2>/dev/null || :; }
  [ -z "$Q_CHILD" ] || { q_stop_tree "$Q_CHILD" "$$"; wait "$Q_CHILD" 2>/dev/null || :; }
  [ -z "$Q_READER" ] || { kill -TERM "$Q_READER" 2>/dev/null || :; wait "$Q_READER" 2>/dev/null || :; }
  printf '오류: 중단됐습니다. 대상·잠금을 보존했습니다. 자원 상태를 확인한 뒤 수동 조정이 필요합니다.\n' >&2
  exit "$1"
}
q_start() {
  [ "$#" = 0 ] || q_error '추가 옵션 없이 실행하세요.'
  ps -o pid= -p "$$" >/dev/null 2>&1 || q_error '실행 시간 제한에 필요한 프로세스 조회가 허용되지 않습니다.'
  q_path "$Q_ROOT/runtime"
  if [ ! -e "$Q_ROOT/runtime" ]; then mkdir "$Q_ROOT/runtime" || q_error 'runtime 폴더를 만들 수 없습니다.'; fi
  q_private_dir "$Q_ROOT/runtime"
  git -C "$Q_ROOT" check-ignore --quiet runtime/quiet-aws/target || q_error 'runtime이 Git 제외 대상이어야 합니다.'
  q_path "$Q_LOCK"; mkdir "$Q_LOCK" 2>/dev/null || q_error '다른 실행 또는 중단된 잠금이 있습니다. 재실행하지 말고 상태를 확인하세요.'
  Q_LOCKED=true
  trap q_finish EXIT
  trap 'q_signal 130' INT
  trap 'q_signal 143' TERM
  trap 'q_signal 129' HUP
  q_path "$Q_DIR"
  unset B6_RUN_PLAN
}
q_identity() {
  if [ -z "${B6_EXPECTED_ACCOUNT:-}" ]; then
    [ -t 0 ] || q_error 'B6_EXPECTED_ACCOUNT와 B6_IAM_USER를 설정하세요.'
    printf '예상 AWS 계정 번호: ' >&2; IFS= read -r -s B6_EXPECTED_ACCOUNT || q_error '입력을 읽지 못했습니다.'; printf '\n' >&2
  fi
  case "$B6_EXPECTED_ACCOUNT" in *[!0-9]*|'') q_error '예상 계정 번호는 숫자 12자리여야 합니다.';; esac
  [ "${#B6_EXPECTED_ACCOUNT}" = 12 ] || q_error '예상 계정 번호는 숫자 12자리여야 합니다.'
  if [ -z "${B6_IAM_USER:-}" ]; then
    [ -t 0 ] || q_error 'B6_IAM_USER를 설정하세요.'
    printf '예상 IAM 사용자 이름: ' >&2; IFS= read -r B6_IAM_USER || q_error '입력을 읽지 못했습니다.'
  fi
  [ -n "$B6_IAM_USER" ] || q_error 'IAM 사용자 이름이 필요합니다.'
  export B6_EXPECTED_ACCOUNT B6_IAM_USER
}
q_mark() { (set -C; printf '%s\n' "$1" > "$Q_DIR/phase-$1") || q_error '단계 기록이 이미 있거나 저장되지 않았습니다.'; sync || q_error '단계 기록 저장에 실패했습니다.'; }
q_target() {
  q_private_dir "$Q_DIR"; q_file "$Q_DIR/target"
  IFS= read -r Q_RUN < "$Q_DIR/target" || q_error '대상 기록을 읽지 못했습니다.'
  case "$Q_RUN" in quiet-*[!a-z0-9-]*|'') q_error '대상 기록이 올바르지 않습니다.';; quiet-*) ;; *) q_error '이 설치 도구가 만든 대상이 아닙니다.';; esac
  [ "${#Q_RUN}" -le 31 ] || q_error '대상 이름이 올바르지 않습니다.'
  Q_STATE="$Q_ROOT/runtime/$Q_RUN-state.json"
  q_path "$Q_STATE"
}
q_log() {
  Q_LOG="$Q_DIR/$1-$(date -u +%Y%m%dT%H%M%S)-$$.log"
  (set -C; : > "$Q_LOG") || q_error '기록 파일을 만들 수 없습니다.'
}
# Keep only controlled lifecycle status lines, not arbitrary stderr or auth payloads.
q_filter() {
  awk '
  /^EC2 .*state=pending$/ {print "QUIET_CLASS=INSTANCE_PENDING"}
  /^EC2 .*state=running$/ {print "QUIET_CLASS=INSTANCE_RUNNING"}
  /Permission denied|REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed|UNPROTECTED PRIVATE KEY|Load key.*(invalid|permissions)/ {print "QUIET_CLASS=SECURITY"}
  /Connection refused|Connection timed out|connect to host.*Operation timed out|cd: \/opt\/b6-1: No such file|PENDING: bootstrap\/container not healthy|Cannot connect to the Docker daemon/ {print "QUIET_CLASS=READINESS"}
  /^BLOCKED: [A-Z0-9_]+$/ || /^result exit=[0-9]+ error_code=[A-Za-z0-9_.]+$/ || /^created_[a-z]+=([a-z]+-[a-f0-9]+)$/ || /^container_health=[a-z]+$/ || /^localhost_(root|health)_http=[0-9]+$/ || /^outbound_tls_http=[0-9]+$/ || /^external_(root|health)_http=200/ || /^CLEANED exact_run=/ || /^DESTROYED_NOOP verified;/ || /^instance=TERMINATED / || /^[a-z]+=EXACT_TYPED_NOT_FOUND$/ {print}
  '
}
q_run() {
  Q_N=$((Q_N+1))
  Q_ATTEMPT="$Q_DIR/attempt-$$-$Q_N.log"
  local fifo="$Q_DIR/pipe-$$-$Q_N" rc reader_rc
  (set -C; : > "$Q_ATTEMPT") || q_error '검증 기록 파일이 이미 있습니다.'
  [ ! -e "$fifo" ] && [ ! -L "$fifo" ] || q_error '통신 경로가 이미 있습니다.'
  mkfifo -m 600 "$fifo" || q_error '전용 통신 경로를 만들 수 없습니다.'
  q_filter < "$fifo" > "$Q_ATTEMPT" & Q_READER=$!
  "$@" > "$fifo" 2>&1 & Q_CHILD=$!
  if [ "${Q_READ_LIMIT:-0}" -gt 0 ]; then
    (trap - EXIT INT TERM HUP; /bin/sleep "$Q_READ_LIMIT"; q_stop_tree "$Q_CHILD" "$$") & Q_WATCH=$!
  fi
  wait "$Q_CHILD"; rc=$?; Q_CHILD=
  if [ -n "$Q_WATCH" ]; then q_stop_tree "$Q_WATCH" "$$"; wait "$Q_WATCH" 2>/dev/null || :; Q_WATCH=; fi
  wait "$Q_READER"; reader_rc=$?; Q_READER=
  rm "$fifo" || q_error '통신 경로 정리에 실패했습니다.'
  cat "$Q_ATTEMPT" >> "$Q_LOG" || q_error '기록 저장에 실패했습니다.'
  [ "$reader_rc" = 0 ] || q_error '출력 보호 처리에 실패했습니다.'
  return "$rc"
}
q_blocked_state() {
  [ -e "$Q_STATE" ] || return 0
  q_file "$Q_STATE"
  jq -e --arg run "$Q_RUN" '.schema==1 and .run_id==$run and (.status=="WORKING" or .status=="ACTIVE" or .status=="DESTROYED") and (.pending // "")=="" and (.capture_waiting // false)!=true' "$Q_STATE" >/dev/null 2>&1 || q_error '결과 불명·미완료·촬영 대기 상태입니다. 수동 확인 전 재실행할 수 없습니다.'
}
q_failed() { q_error '실행에 실패했습니다. 대상과 오류 기록을 확인하세요. 결과 불명·미완료 상태에서는 재실행하지 마세요.'; }

q_archive() {
  # Exclusive private parent prevents mv from merging into an old record.
  local archive="$Q_ROOT/runtime/quiet-completed-$Q_RUN"
  q_path "$archive"
  mkdir "$archive" 2>/dev/null || q_error '완료 기록 경로가 이미 있습니다. 덮어쓰지 않습니다.'
  mv -n "$Q_DIR" "$archive/record" || q_error '완료 기록 보관에 실패했습니다.'
  [ ! -e "$Q_DIR" ] && [ -f "$archive/record/target" ] || q_error '완료 기록 이동을 확인하지 못했습니다.'
  sync || q_error '완료 기록 저장에 실패했습니다.'
  Q_LOG=
}

# Reuse the engine's identity/state/ownership guards without status.sh's
# capture_refs (which writes state). This subshell emits one controlled field.
q_read_compute_state() (
  . "$Q_ROOT/scripts/common.sh"
  parse --state "$Q_STATE"
  identity; load_state
  [ "$(sget '.status')" = ACTIVE ] || fail ACTIVE_STATE_REQUIRED
  resource instance
  $PRESENT || fail INSTANCE_ABSENT
  printf 'EC2 observed state=%s\n' "$(printf '%s' "$OBJ" | jq -r '.State.Name')"
)
