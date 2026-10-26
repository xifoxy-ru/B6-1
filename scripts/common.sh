#!/bin/bash
# Bash 3.2; visible AWS CLI calls/queries, preinstalled jq for API JSON and data-only state.
set +x
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
AWS_BIN=${B6_AWS_BIN:-aws}
PROFILE=b6-1-iam
REGION=ap-northeast-2
STATE="$ROOT/runtime/shell-state.json"
RUN_ID=
APPLY=false
CAPTURE=false
CAPTURE_ALLOWED=false
SECTION=all
EXPECTED_ACCOUNT=${B6_EXPECTED_ACCOUNT:-}
EXPECTED_USER=${B6_IAM_USER:-}
INPUT_JSON=
API_RESULT=
API_CODE=
API_RC=0
fail() { printf 'BLOCKED: %s\n' "$1" >&2; exit 1; }
need() { if ! "$@"; then fail GUARD_FAILED; fi; }
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
sha() { shasum -a 256 | awk '{print $1}'; }
parse() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply) APPLY=true; shift;;
      --capture) CAPTURE=true; shift;;
      --state|--profile|--region|--run-id|--section) [ "$#" -ge 2 ] || fail OPTION_VALUE_REQUIRED
        case "$1" in --state) STATE=$2;; --profile) PROFILE=$2;; --region) REGION=$2;; --run-id) RUN_ID=$2;; --section) SECTION=$2;; esac; shift 2;;
      --help) printf 'Options: --state PATH --profile PROFILE --region ap-northeast-2 --run-id UNIQUE --apply [--capture: create/destroy nativeTTY only]\n'; exit 0;;
      *) fail UNKNOWN_OPTION;;
    esac
  done
  if $CAPTURE; then
    $CAPTURE_ALLOWED || fail CAPTURE_CREATE_DESTROY_ONLY
    [ -t 0 ] && [ -t 1 ] || fail CAPTURE_NATIVE_TTY_REQUIRED_BEFORE_WRITES
  fi
  [ "$REGION" = ap-northeast-2 ] || fail SEOUL_ONLY
  case "$STATE" in /*) ;; *) STATE="$ROOT/$STATE";; esac
  case "/$STATE/" in */../*|*/./*) fail PATH_TRAVERSAL;; esac
  case "$STATE" in "$ROOT/runtime/"*) ;; *) fail STATE_OUTSIDE_RUNTIME;; esac
  check_path "$STATE"
  command -v jq >/dev/null || fail INSTALLED_JQ_REQUIRED_NO_INSTALL
}
# Capture checkpoints never replay stdout or clear a prior screen.
capture_abort() {
  printf '\n촬영 중단: 다음 그룹은 실행하지 않습니다. state=%s\n' "$STATE" >&2
  printf '현재 자원/비용이 남을 수 있습니다. 같은 create/destroy를 다시 실행하지 말고 PM에게 부분 상태 검토를 요청하세요.\n' >&2
  exit "$1"
}
capture_checkpoint() {
  $CAPTURE || return 0
  [ -t 0 ] && [ -t 1 ] || fail CAPTURE_TTY_LOST
  local id=$1 title=$2 file=$3 next=$4 reply
  # If EOF/interrupt occurs, this marker remains and load_state refuses mutation.
  write_state '.capture_waiting=true|.capture_checkpoint=$id' --arg id "$id"
  printf '\n=== 촬영: %s ===\nPNG 파일: %s\n' "$title" "$file"
  printf '위의 실제 명령/결과를 촬영하세요. 길면 같은 화면에서 -part1/-part2 파일로 나누세요.\n'
  printf '다음: %s\nPM 확인 후 촬영을 저장했을 때만 Enter. 중단은 Ctrl-C.\n' "$next"
  trap 'capture_abort 130' INT
  trap 'capture_abort 143' TERM
  trap 'capture_abort 129' HUP
  while :; do
    if ! IFS= read -r reply; then capture_abort 1; fi
    [ -z "$reply" ] && break
    printf '자동 진행하지 않습니다. 저장/PM 확인 후 빈 Enter만 누르세요.\n'
  done
  trap - INT TERM HUP
  write_state 'del(.capture_waiting,.capture_checkpoint)'
}
check_path() {
  local p=$1
  while [ "$p" != / ] && [ -n "$p" ]; do
    [ ! -L "$p" ] || fail SYMLINK_FORBIDDEN
    p=$(dirname -- "$p")
  done
}
write_state() {
  local expression=$1; shift
  local tmp="${STATE}.tmp.$$"
  check_path "$STATE"
  [ ! -e "$tmp" ] || fail STATE_TEMP_COLLISION
  (umask 077; set -C; jq "$@" "$expression" "$STATE" > "$tmp") || fail STATE_WRITE_FAILED
  chmod 600 "$tmp"; sync || fail STATE_SYNC_FAILED
  mv -f "$tmp" "$STATE" || fail STATE_REPLACE_FAILED
  sync || fail STATE_SYNC_FAILED
}
sget() { jq -r "$1 // empty" "$STATE"; }
request() {
  local query=$1; shift
  local cmd=("$@")
  [ "${cmd[0]}" = aws ] || fail AWS_COMMAND_REQUIRED
  cmd[0]=$AWS_BIN
  printf '$ '
  printf '%q ' "${cmd[@]}" --profile "$PROFILE" --region "$REGION" --query "$query" --output json --no-cli-pager
  if [ -n "$INPUT_JSON" ]; then printf '%q ' --ip-permissions file:///dev/stdin; fi
  printf '\n'
  if [ -n "$INPUT_JSON" ]; then
    printf '%s' "$INPUT_JSON" | jq -c '(.[]? | select(.FromPort==22) | .IpRanges[].CidrIp)="PUBLIC_IPV4_MASKED/32"' | sed 's/^/# actual stdin JSON; sensitive source masked: /'
    API_RESULT=$(printf '%s' "$INPUT_JSON" | "${cmd[@]}" --profile "$PROFILE" --region "$REGION" --query "$query" --output json --no-cli-pager --ip-permissions file:///dev/stdin 2>&1)
    API_RC=$?
  else
    API_RESULT=$("${cmd[@]}" --profile "$PROFILE" --region "$REGION" --query "$query" --output json --no-cli-pager 2>&1)
    API_RC=$?
  fi
  API_CODE=
  if [ "$API_RC" -ne 0 ]; then API_CODE=$(printf '%s' "$API_RESULT" | sed -n 's/.*An error occurred (\([^)]*\)).*/\1/p' | head -n 1); fi
  printf 'result exit=%s error_code=%s\n' "$API_RC" "${API_CODE:-NONE}"
}
okay() { [ "$API_RC" -eq 0 ] || fail "AWS_ERROR_${API_CODE:-AUTH_OR_NETWORK}_NOT_ABSENCE"; }
identity() {
  case "$EXPECTED_ACCOUNT" in *[!0-9]*|'') fail EXPECTED_ACCOUNT_REQUIRED;; esac
  [ "${#EXPECTED_ACCOUNT}" -eq 12 ] || fail EXPECTED_ACCOUNT_12_DIGITS
  [ -n "$EXPECTED_USER" ] || fail EXPECTED_IAM_USER_REQUIRED
  request '[Account,Arn]' aws sts get-caller-identity; okay
  local account arn
  account=$(printf '%s' "$API_RESULT" | jq -r '.[0]'); arn=$(printf '%s' "$API_RESULT" | jq -r '.[1]')
  [ "$account" = "$EXPECTED_ACCOUNT" ] && [ "$arn" = "arn:aws:iam::$EXPECTED_ACCOUNT:user/$EXPECTED_USER" ] || fail WRONG_ACCOUNT_OR_PRINCIPAL
  printf 'identity=EXPECTED_IAM_USER_MATCH account=[MASKED] arn=[MASKED]\n'
}
load_state() {
  [ -f "$STATE" ] && [ "$(mode "$STATE")" = 600 ] || fail SECURE_STATE_REQUIRED
  [ -O "$STATE" ] || fail STATE_OWNER_MISMATCH
  [ "$(sget '.region')" = "$REGION" ] && [ "$(sget '.profile')" = "$PROFILE" ] || fail STATE_CONTEXT_MISMATCH
  RUN_ID=$(sget '.run_id'); valid_run
  local binding
  binding=$(printf '%s:%s' "$(sget '.account_salt')" "$EXPECTED_ACCOUNT" | sha)
  [ "$binding" = "$(sget '.account_binding')" ] && [ "$EXPECTED_USER" = "$(sget '.iam_user')" ] || fail STATE_IDENTITY_MISMATCH
  if [ "${READ_ONLY_STATUS:-false}" != true ]; then
    [ "$(sget '.capture_waiting')" != true ] || fail CAPTURE_PAUSED_REQUIRES_REVIEW_NO_RERUN
    [ "$(sget '.status')" != UNKNOWN ] && [ -z "$(sget '.pending')" ] || fail UNKNOWN_OUTCOME_REQUIRES_MANUAL_RECONCILIATION; fi
  jq -e '.schema==1 and (.refs|type)=="object" and (.refs|to_entries|all(.[]; . as $e | ({vpc:"vpc",subnet:"subnet",igw:"igw",rt:"rtb",assoc:"rtbassoc",sg:"sg",key:"key",instance:"i",volume:"vol",eni:"eni"}[$e.key]) as $p | $p!=null and ($e.value|type)=="string" and ($e.value|test("^"+$p+"-[0-9a-f]{8,17}$"))))' "$STATE" >/dev/null || fail INVALID_RESOURCE_IDS
}
valid_run() { case "$RUN_ID" in ''|*[!a-z0-9-]*|[-]*) fail INVALID_RUN_ID;; esac; [ "${#RUN_ID}" -ge 3 ] && [ "${#RUN_ID}" -le 31 ] || fail INVALID_RUN_ID; }
name() { printf 'b6-1-%s-%s' "$RUN_ID" "$1"; }
tags() { jq -nc --arg run "$RUN_ID" --arg name "$(name "$2")" --arg kind "$1" '[{ResourceType:$kind,Tags:[{Key:"Project",Value:"B6-1"},{Key:"RunId",Value:$run},{Key:"Name",Value:$name}]}]'; }
source_ip() {
  [ -z "${HTTPS_PROXY:-}${HTTP_PROXY:-}${ALL_PROXY:-}${https_proxy:-}${http_proxy:-}${all_proxy:-}" ] || fail PROXY_REQUIRES_REVIEW
  SOURCE=$(curl --fail --silent --show-error --noproxy '*' --proto '=https' --tlsv1.2 https://checkip.amazonaws.com 2>/dev/null) || fail IP_LOOKUP_FAILED
  # Strict dotted global-unicast IPv4. No parsing/logging/hash outside memory.
  printf '%s\n' "$SOURCE" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i!~/^[0-9]+$/||$i>255||($i~/^0[0-9]/))exit 1; if($1==0||$1==10||$1==127||$1>=224||($1==169&&$2==254)||($1==172&&$2>=16&&$2<=31)||($1==192&&$2==168)||($1==100&&$2>=64&&$2<=127)||($1==198&&($2==18||$2==19))||($1==192&&$2==0)||($1==198&&$2==51&&$3==100)||($1==203&&$2==0&&$3==113))exit 1}' || fail GLOBAL_IPV4_REQUIRED
}
mutate() {
  local kind=$1 query=$2; shift 2
  [ "$(sget '.status')" != UNKNOWN ] || fail UNKNOWN_OUTCOME_NO_RETRY
  request null "$@" --dry-run
  [ "$API_CODE" = DryRunOperation ] || fail DRY_RUN_NOT_AUTHORIZED
  if [ "${3:-}" = authorize-security-group-ingress ]; then
    local old=$SOURCE; source_ip; [ "$SOURCE" = "$old" ] || fail SOURCE_IP_CHANGED
  fi
  write_state '.status="UNKNOWN" | .pending=$op' --arg op "$3"
  request "$query" "$@"
  [ "$API_RC" -eq 0 ] || fail UNKNOWN_OUTCOME_NO_BLIND_RETRY
  if [ "$kind" != - ]; then
    local id; id=$(printf '%s' "$API_RESULT" | jq -er 'select(type=="string" and test("^[a-z]+-[0-9a-f]{8,17}$"))') || fail UNKNOWN_CREATED_REFERENCE
    write_state '.refs[$kind]=$id | .status="WORKING" | del(.pending)' --arg kind "$kind" --arg id "$id"
    printf 'created_%s=%s\n' "$kind" "$id"
  else
    write_state '.status="WORKING" | del(.pending)'
  fi
}
resource() {
  local kind=$1 id; id=$(sget ".refs.$kind"); OBJ=; PRESENT=false
  [ -n "$id" ] || return 0
  case "$kind" in
    vpc) request 'Vpcs[0]' aws ec2 describe-vpcs --vpc-ids "$id"; expected=InvalidVpcID.NotFound;;
    subnet) request 'Subnets[0]' aws ec2 describe-subnets --subnet-ids "$id"; expected=InvalidSubnetID.NotFound;;
    igw) request 'InternetGateways[0]' aws ec2 describe-internet-gateways --internet-gateway-ids "$id"; expected=InvalidInternetGatewayID.NotFound;;
    rt) request 'RouteTables[0]' aws ec2 describe-route-tables --route-table-ids "$id"; expected=InvalidRouteTableID.NotFound;;
    sg) request 'SecurityGroups[0]' aws ec2 describe-security-groups --group-ids "$id"; expected=InvalidGroup.NotFound;;
    key) request 'KeyPairs[0]' aws ec2 describe-key-pairs --key-pair-ids "$id"; expected=InvalidKeyPair.NotFound;;
    instance) request 'Reservations[0]' aws ec2 describe-instances --instance-ids "$id"; expected=InvalidInstanceID.NotFound;;
    volume) request 'Volumes[0]' aws ec2 describe-volumes --volume-ids "$id"; expected=InvalidVolume.NotFound;;
    eni) request 'NetworkInterfaces[0]' aws ec2 describe-network-interfaces --network-interface-ids "$id"; expected=InvalidNetworkInterfaceID.NotFound;;
    *) fail UNKNOWN_RESOURCE_KIND;;
  esac
  if [ "$API_RC" -ne 0 ]; then [ "$API_CODE" = "$expected" ] || fail "${kind}_ERROR_NOT_ABSENCE"; return 0; fi
  OBJ=$API_RESULT
  printf '%s' "$OBJ" | jq -e 'type=="object"' >/dev/null || fail MALFORMED_RESOURCE_OBJECT
  [ "$OBJ" != null ] || fail EMPTY_UNTYPED_RESPONSE
  if [ "$kind" = instance ]; then
    [ "$(printf '%s' "$OBJ" | jq -r '.OwnerId')" = "$EXPECTED_ACCOUNT" ] || fail INSTANCE_OWNER_MISMATCH
    OBJ=$(printf '%s' "$OBJ" | jq -e '.Instances | select(length==1) | .[0]') || fail INSTANCE_COUNT_MISMATCH
  fi
  local owner; owner=$(printf '%s' "$OBJ" | jq -r '.OwnerId // empty')
  [ -z "$owner" ] || [ "$owner" = "$EXPECTED_ACCOUNT" ] || fail RESOURCE_OWNER_MISMATCH
  case "$kind" in vpc|subnet|sg|rt|eni) [ "$owner" = "$EXPECTED_ACCOUNT" ] || fail OWNER_FIELD_REQUIRED;; esac
  if [ "$kind" != eni ]; then
    local tagkind=$kind; case "$kind" in instance|volume) tagkind=web;; esac
    printf '%s' "$OBJ" | jq -e --arg run "$RUN_ID" --arg name "$(name "$tagkind")" '.Tags as $t | ($t|map(select(.Key=="Project" and .Value=="B6-1"))|length)==1 and ($t|map(select(.Key=="RunId" and .Value==$run))|length)==1 and ($t|map(select(.Key=="Name" and .Value==$name))|length)==1' >/dev/null || fail RESOURCE_TAG_MISMATCH
  fi
  case "$kind" in
    vpc) [ "$(printf '%s' "$OBJ" | jq -r '.IsDefault')" = false ] && [ "$(printf '%s' "$OBJ" | jq -r '.CidrBlock')" = 10.0.0.0/16 ] || fail DEFAULT_OR_WRONG_VPC;;
    subnet|rt|sg|eni) [ "$(printf '%s' "$OBJ" | jq -r '.VpcId')" = "$(sget '.refs.vpc')" ] || fail VPC_LINK_MISMATCH;;
  esac
  if [ "$kind" = key ]; then [ "$(printf '%s' "$OBJ" | jq -r ' .KeyName')" = "$(sget '.key_name')" ] && [ "$(printf '%s' "$OBJ" | jq -r '.KeyType')" = ed25519 ] && [ "$(printf '%s' "$OBJ" | jq -r '.KeyFingerprint')" = "$(sget '.key_fingerprint')" ] || fail KEY_IDENTITY_MISMATCH; fi
  if [ "$kind" = eni ]; then [ "$(printf '%s' "$OBJ" | jq -r '.Attachment.InstanceId')" = "$(sget '.refs.instance')" ] || fail ENI_INSTANCE_MISMATCH; fi
  if [ "$kind" = rt ]; then printf '%s' "$OBJ" | jq -e 'all(.Associations[]; .Main!=true)' >/dev/null || fail MAIN_RT_FORBIDDEN; fi
  PRESENT=true
}
plan() { printf 'PLAN ONLY: %s; Seoul t4g.nano / encrypted8GiB / standard credits / autoIPv4; no AWS writes. Explicit --apply required.\n' "$1"; }
capture_refs() {
  resource instance
  $PRESENT || return 0
  [ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" != terminated ] || return 0
  [ "$(printf '%s' "$OBJ" | jq -r '.VpcId')" = "$(sget '.refs.vpc')" ] && [ "$(printf '%s' "$OBJ" | jq -r '.KeyName')" = "$(sget '.key_name')" ] || fail INSTANCE_LINK_MISMATCH
  printf '%s' "$OBJ" | jq -e '(.BlockDeviceMappings|length)==1 and (.NetworkInterfaces|length)==1 and .BlockDeviceMappings[0].Ebs.DeleteOnTermination and .NetworkInterfaces[0].Attachment.DeleteOnTermination' >/dev/null || fail COLLATERAL_DISK_OR_ENI
  local volume eni old
  volume=$(printf '%s' "$OBJ" | jq -r '.BlockDeviceMappings[0].Ebs.VolumeId'); eni=$(printf '%s' "$OBJ" | jq -r '.NetworkInterfaces[0].NetworkInterfaceId')
  old=$(sget '.refs.volume'); [ -z "$old" ] || [ "$old" = "$volume" ] || fail ROOT_VOLUME_CHANGED
  old=$(sget '.refs.eni'); [ -z "$old" ] || [ "$old" = "$eni" ] || fail ENI_CHANGED
  write_state '.refs.volume=$v|.refs.eni=$e' --arg v "$volume" --arg e "$eni"
  resource volume
  $PRESENT && printf '%s' "$OBJ" | jq -e '.Size==8 and .VolumeType=="gp3" and .Encrypted' >/dev/null || fail ROOT_DISK_GUARD
  resource eni
  $PRESENT && [ "$(printf '%s' "$OBJ" | jq -r '.Attachment.InstanceId')" = "$(sget '.refs.instance')" ] || fail ENI_LINK_MISMATCH
}
foreign_guard() {
  resource vpc; $PRESENT || return 0
  local vpc k query ids id allowed
  vpc=$(sget '.refs.vpc')
  for k in subnet sg rt eni; do
    case "$k" in
      subnet) request 'Subnets[].SubnetId' aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc";;
      sg) request 'SecurityGroups[?GroupName!=`default`].GroupId' aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc";;
      rt) request 'RouteTables[?!contains(Associations[].Main, `true`)].RouteTableId' aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc";;
      eni) request 'NetworkInterfaces[].NetworkInterfaceId' aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc";;
    esac
    okay; printf '%s' "$API_RESULT" | jq -e 'type=="array"' >/dev/null || fail MALFORMED_DEPENDENCY_ARRAY
    ids=$(printf '%s' "$API_RESULT" | jq -r '.[]') || fail DEPENDENCY_PARSE_ERROR; allowed=$(sget ".refs.$k")
    for id in $ids; do [ "$id" = "$allowed" ] || fail FOREIGN_VPC_DEPENDENCY; resource "$k"; done
  done
  request 'Reservations[].Instances[].InstanceId' aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down; okay
  printf '%s' "$API_RESULT" | jq -e 'type=="array"' >/dev/null || fail MALFORMED_DEPENDENCY_ARRAY
  ids=$(printf '%s' "$API_RESULT" | jq -r '.[]') || fail DEPENDENCY_PARSE_ERROR; for id in $ids; do [ "$id" = "$(sget '.refs.instance')" ] || fail FOREIGN_INSTANCE; done
  request 'InternetGateways[].InternetGatewayId' aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc"; okay
  printf '%s' "$API_RESULT" | jq -e 'type=="array"' >/dev/null || fail MALFORMED_DEPENDENCY_ARRAY
  ids=$(printf '%s' "$API_RESULT" | jq -r '.[]') || fail DEPENDENCY_PARSE_ERROR; for id in $ids; do [ "$id" = "$(sget '.refs.igw')" ] || fail FOREIGN_IGW; done
}
