#!/bin/bash
# Connect only to the exact current quiet-install target; never discover a latest run.
set +x
set +e
set -u
[ ! -L "$0" ] || { printf '오류: 스크립트 링크는 사용할 수 없습니다.\n' >&2; exit 1; }
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
. "$BASE/scripts/common.sh"
exec 3>&2
fail() { printf '오류: 대상·신원·파일 검사를 통과하지 못했습니다 (%s). 상태를 확인하세요.\n' "$1" >&3; exit 1; }
[ "$#" = 0 ] || fail NO_OPTIONS_ALLOWED
command -v jq >/dev/null || fail INSTALLED_JQ_REQUIRED
Q="$ROOT/runtime/quiet-aws"
secure_dir() { check_path "$1"; [ -d "$1" ] && [ -O "$1" ] && [ "$(mode "$1")" = 700 ] || fail DIRECTORY_OWNER_MODE; }
secure_file() { check_path "$1"; [ -f "$1" ] && [ -O "$1" ] && [ "$(mode "$1")" = 600 ] || fail FILE_OWNER_MODE; }
no_lock() { [ ! -e "$ROOT/runtime/.quiet-aws.lock" ] && [ ! -L "$ROOT/runtime/.quiet-aws.lock" ] || fail LIFECYCLE_BUSY_OR_INTERRUPTED; }
secure_dir "$ROOT/runtime"; no_lock; secure_dir "$Q"; secure_file "$Q/target"
IFS= read -r TARGET < "$Q/target" || fail TARGET_MISSING
[[ "$TARGET" =~ ^quiet-[a-z0-9-]+$ ]] && [ "${#TARGET}" -le 31 ] || fail INVALID_TARGET
[ "$(wc -l < "$Q/target" | tr -d ' ')" = 1 ] || fail TARGET_FORMAT
STATE="$ROOT/runtime/$TARGET-state.json"
secure_file "$STATE"
STATE_HASH=$(sha < "$STATE")
jq -e --arg run "$TARGET" '.schema==1 and .run_id==$run and .profile=="b6-1-iam" and .region=="ap-northeast-2" and .status=="ACTIVE" and (.pending // "")=="" and (.capture_waiting // false)!=true and (.account_salt|type)=="string" and (.account_salt|test("^[0-9a-f]{48}$")) and (.account_binding|type)=="string" and (.account_binding|test("^[0-9a-f]{64}$")) and (.iam_user|type)=="string" and (.iam_user|test("^[A-Za-z0-9+=,.@_-]{1,64}$"))' "$STATE" >/dev/null 2>&1 || fail ACTIVE_ORIGINAL_STATE_REQUIRED
ORIGINAL_USER=$(jq -r '.iam_user' "$STATE")
# Raw identity stays in memory. It must match original stored trust, not itself.
OBSERVED=$("$AWS_BIN" sts get-caller-identity --profile b6-1-iam --region ap-northeast-2 --query '[Account,Arn]' --output json --no-cli-pager 2>&1)
rc=$?
if [ "$rc" != 0 ]; then
  printf '오류: CLI 인증 또는 연결을 확인하세요. 필요하면 별도 터미널에서 aws login --profile b6-1-iam --region ap-northeast-2 --remote 를 실행하세요.\n' >&2
  exit 1
fi
ACCOUNT=$(printf '%s' "$OBSERVED" | jq -er '.[0]|select(type=="string" and test("^[0-9]{12}$"))' 2>/dev/null) || fail IDENTITY_RESPONSE
ARN=$(printf '%s' "$OBSERVED" | jq -er '.[1]|select(type=="string")' 2>/dev/null) || fail IDENTITY_RESPONSE
BINDING=$(printf '%s:%s' "$(jq -r '.account_salt' "$STATE")" "$ACCOUNT" | sha)
[ "$BINDING" = "$(jq -r '.account_binding' "$STATE")" ] && [ "$ARN" = "arn:aws:iam::$ACCOUNT:user/$ORIGINAL_USER" ] || fail ORIGINAL_IAM_IDENTITY_MISMATCH
[ -z "${B6_EXPECTED_ACCOUNT:-}" ] || [ "$B6_EXPECTED_ACCOUNT" = "$ACCOUNT" ] || fail EXPECTED_ACCOUNT_MISMATCH
[ -z "${B6_IAM_USER:-}" ] || [ "$B6_IAM_USER" = "$ORIGINAL_USER" ] || fail EXPECTED_USER_MISMATCH
EXPECTED_ACCOUNT=$ACCOUNT; EXPECTED_USER=$ORIGINAL_USER
unset OBSERVED ARN ACCOUNT BINDING
load_state >/dev/null 2>&1 || fail ORIGINAL_STATE_GUARD
for k in instance vpc subnet sg key; do [ -n "$(sget ".refs.$k")" ] || fail ORIGINAL_REFERENCE_REQUIRED; done
[ "$(sget '.key_name')" = "b6-1-$RUN_ID-key" ] || fail ORIGINAL_KEY_NAME
KEY="$ROOT/.secrets/key-$RUN_ID.pem"
[ "$(sget '.key_path')" = "$KEY" ] || fail ORIGINAL_KEY_PATH
secure_dir "$ROOT/.secrets"; secure_file "$KEY"
git -C "$ROOT" check-ignore --quiet -- "$KEY" || fail PRIVATE_FILE_NOT_IGNORED
resource instance >/dev/null 2>&1 || fail INSTANCE_READ_OR_OWNER_TAG_GUARD
$PRESENT || fail INSTANCE_ABSENT
printf '%s' "$OBJ" | jq -e --arg id "$(sget '.refs.instance')" --arg vpc "$(sget '.refs.vpc')" --arg subnet "$(sget '.refs.subnet')" --arg sg "$(sget '.refs.sg')" --arg key "$(sget '.key_name')" '.InstanceId==$id and .State.Name=="running" and .VpcId==$vpc and .SubnetId==$subnet and .KeyName==$key and (.SecurityGroups|length)==1 and .SecurityGroups[0].GroupId==$sg and (.NetworkInterfaces|length)==1 and (.BlockDeviceMappings|length)==1 and .NetworkInterfaces[0].Attachment.DeleteOnTermination==true and .BlockDeviceMappings[0].Ebs.DeleteOnTermination==true' >/dev/null 2>&1 || fail INSTANCE_LINK_OR_RUNNING_GUARD
for pair in 'eni .NetworkInterfaces[0].NetworkInterfaceId' 'volume .BlockDeviceMappings[0].Ebs.VolumeId'; do
  read -r k field <<< "$pair"
  original=$(sget ".refs.$k")
  [ -z "$original" ] || [ "$original" = "$(printf '%s' "$OBJ" | jq -r "$field")" ] || fail ORIGINAL_DISK_OR_NETWORK_CHANGED
done
SERVER=$(printf '%s' "$OBJ" | jq -er '.PublicIpAddress|select(type=="string")' 2>/dev/null) || fail PUBLIC_IPV4_REQUIRED
printf '%s\n' "$SERVER" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i!~/^[0-9]+$/||$i>255||($i~/^0[0-9]/))exit 1;if($1==0||$1==10||$1==127||$1>=224||($1==169&&$2==254)||($1==172&&$2>=16&&$2<=31)||($1==192&&$2==168)||($1==100&&$2>=64&&$2<=127)||($1==198&&($2==18||$2==19))||($1==192&&$2==0)||($1==198&&$2==51&&$3==100)||($1==203&&$2==0&&$3==113))exit 1}' || fail PUBLIC_IPV4_INVALID
HOSTS="$ROOT/runtime/$RUN_ID-known_hosts"
check_path "$HOSTS"
[ -f "$HOSTS" ] && [ -s "$HOSTS" ] && [ -O "$HOSTS" ] || fail PINNED_HOST_FILE_REQUIRED
hm=$(mode "$HOSTS")
[[ "$hm" =~ ^[0-7]{3}$ ]] && [ "$((8#$hm & 022))" = 0 ] || fail HOST_FILE_WRITABLE_BY_OTHERS
ssh-keygen -F "$SERVER" -f "$HOSTS" >/dev/null 2>&1 || fail PINNED_HOST_ENTRY_REQUIRED
no_lock
[ "$(cat "$Q/target")" = "$TARGET" ] && [ "$(sha < "$STATE")" = "$STATE_HASH" ] || fail TARGET_STATE_CHANGED
unset EXPECTED_ACCOUNT EXPECTED_USER ORIGINAL_USER API_RESULT OBJ
# No user config, proxy, remote command or option passthrough. Host/key bytes untouched.
exec 3>&-
ssh -F /dev/null -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$HOSTS" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 -i "$KEY" "ec2-user@$SERVER"
rc=$?
[ "$rc" = 0 ] || printf '오류: SSH 연결이 종료됐습니다. 현재 IP 제한·인증·호스트 키를 확인하세요.\n' >&2
exit "$rc"
