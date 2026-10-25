#!/bin/bash
set +x
. "$(dirname -- "$0")/common.sh"
parse "$@"
if ! $APPLY; then
  plan create
  [ -n "$RUN_ID" ] || { printf 'To prepare a read-only run plan, supply --run-id UNIQUE and configured expected identity.\n'; exit 0; }
  valid_run; identity
  PLAN_FILE=${B6_RUN_PLAN:-$ROOT/runtime/$RUN_ID-plan.json}
  check_path "$PLAN_FILE"
  case "$PLAN_FILE" in "$ROOT/runtime/"*) ;; *) fail PLAN_OUTSIDE_RUNTIME;; esac
  [ ! -e "$PLAN_FILE" ] || { printf 'Existing immutable plan: %s (not overwritten)\n' "$PLAN_FILE"; exit 0; }
  request 'sort_by(Images,&CreationDate)[-1]' aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-minimal-2023.*-arm64' Name=architecture,Values=arm64 Name=state,Values=available Name=virtualization-type,Values=hvm Name=root-device-type,Values=ebs
  okay
  PLAN_AMI=$(printf '%s' "$API_RESULT" | jq -er '.ImageId') || fail NO_AMI
  [ "$(printf '%s' "$API_RESULT" | jq -r '.ImageOwnerAlias')" = amazon ] || fail AMI_OWNER
  mkdir -p "$ROOT/runtime"; chmod 700 "$ROOT/runtime"
  PREVIEW="$ROOT/runtime/$RUN_ID-preview.sh"
  "$ROOT/deploy/render-user-data.sh" --output "$PREVIEW" || fail PLAN_RENDER_FAILED
  HASH=$(sha < "$PREVIEW")
  (umask 077; set -C; jq -nc --arg run "$RUN_ID" --arg ami "$PLAN_AMI" --arg hash "$HASH" '{run_id:$run,ami:$ami,az:"ap-northeast-2a",user_data_sha256:$hash,instance_type:"t4g.nano",root_gib:8,volume_type:"gp3",encrypted:true,cpu_credits:"standard",metadata_tokens:"required",public_ipv4:true,iam_role:false,paid_create:false,capture_before_cleanup:true}' > "$PLAN_FILE") || fail EXCLUSIVE_PLAN_FAILED
  printf 'READ_ONLY_PLAN_READY=%s ami=%s userdata_sha256=%s paid_create=false\n' "$PLAN_FILE" "$PLAN_AMI" "$HASH"
  exit 0
fi
valid_run
identity
B6_RUN_PLAN=${B6_RUN_PLAN:-$ROOT/runtime/$RUN_ID-plan.json}
[ ! -e "$STATE" ] || fail STATE_EXISTS_NO_SILENT_RECREATE
[ -n "${B6_RUN_PLAN:-}" ] && [ -f "$B6_RUN_PLAN" ] || fail REVIEWED_RUN_PLAN_REQUIRED
[ "$(jq -r '.run_id' "$B6_RUN_PLAN")" = "$RUN_ID" ] || fail RUN_PLAN_MISMATCH
AMI=$(jq -r '.ami' "$B6_RUN_PLAN")
UD_HASH=$(jq -r '.user_data_sha256' "$B6_RUN_PLAN")
KEY_NAME=$(name key); KEY_PATH="$ROOT/.secrets/key-$RUN_ID.pem"
check_path "$KEY_PATH"
[ ! -e "$KEY_PATH" ] || fail EXISTING_PRIVATE_FILE_NO_OVERWRITE
git -C "$ROOT" check-ignore -- "$KEY_PATH" >/dev/null || fail PRIVATE_FILE_NOT_IGNORED
request 'KeyPairs' aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEY_NAME"; okay
[ "$(printf '%s' "$API_RESULT" | jq length)" = 0 ] || fail CLOUD_KEY_COLLISION
request 'Vpcs' aws ec2 describe-vpcs --filters Name=tag:Project,Values=B6-1 "Name=tag:RunId,Values=$RUN_ID"; okay
[ "$(printf '%s' "$API_RESULT" | jq length)" = 0 ] || fail RUN_COLLISION
request 'Images[0]' aws ec2 describe-images --owners amazon --image-ids "$AMI"; okay
owner=$(printf '%s' "$API_RESULT" | jq -r '.ImageOwnerAlias'); arch=$(printf '%s' "$API_RESULT" | jq -r '.Architecture')
[ "$owner" = amazon ] && [ "$arch" = arm64 ] && [ "$(printf '%s' "$API_RESULT" | jq -r '.State')" = available ] || fail AMI_NOT_TRUSTED_ARM64
[ "$(printf '%s' "$API_RESULT" | jq -r '.VirtualizationType')" = hvm ] && [ "$(printf '%s' "$API_RESULT" | jq -r '.RootDeviceType')" = ebs ] || fail AMI_TYPE
ROOT_DEVICE=$(printf '%s' "$API_RESULT" | jq -r '.RootDeviceName')
minimum=$(printf '%s' "$API_RESULT" | jq -r --arg root "$ROOT_DEVICE" '.BlockDeviceMappings[]|select(.DeviceName==$root)|.Ebs.VolumeSize')
[ "$minimum" -le 8 ] || fail AMI_ROOT_TOO_LARGE_NO_FALLBACK
request 'InstanceTypes[0].[MemoryInfo.SizeInMiB,ProcessorInfo.SupportedArchitectures]' aws ec2 describe-instance-types --instance-types t4g.nano; okay
[ "$(printf '%s' "$API_RESULT" | jq -r '.[0]')" = 512 ] && printf '%s' "$API_RESULT" | jq -e '.[1]|index("arm64")!=null' >/dev/null || fail NANO_ARM64_UNSUPPORTED
source_ip
AZ=$(jq -r '.az' "$B6_RUN_PLAN")
request 'AvailabilityZones' aws ec2 describe-availability-zones --zone-names "$AZ" --filters Name=state,Values=available Name=zone-type,Values=availability-zone; okay
[ "$(printf '%s' "$API_RESULT" | jq length)" = 1 ] || fail AZ_UNAVAILABLE
umask 077
mkdir -p "$ROOT/runtime" "$ROOT/.secrets"
chmod 700 "$ROOT/runtime" "$ROOT/.secrets"
mkdir "$ROOT/runtime/.run-$RUN_ID.lock" || fail RUN_ID_ALREADY_USED
salt=$(LC_ALL=C od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
binding=$(printf '%s:%s' "$salt" "$EXPECTED_ACCOUNT" | sha)
(set -C; jq -nc --arg run "$RUN_ID" --arg profile "$PROFILE" --arg region "$REGION" --arg salt "$salt" --arg binding "$binding" --arg user "$EXPECTED_USER" --arg key "$KEY_NAME" --arg path "$KEY_PATH" '{schema:1,run_id:$run,profile:$profile,region:$region,account_salt:$salt,account_binding:$binding,iam_user:$user,key_name:$key,key_path:$path,status:"WORKING",refs:{}}' > "$STATE") || fail EXCLUSIVE_STATE_FAILED
sync
USER_DATA="$ROOT/runtime/$RUN_ID-user-data.sh"
"$ROOT/deploy/render-user-data.sh" --output "$USER_DATA" || fail RENDER_FAILED
[ "$(sha < "$USER_DATA")" = "$UD_HASH" ] || fail REVIEWED_USERDATA_DRIFT
mutate vpc 'Vpc.VpcId' aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "$(tags vpc vpc)"
mutate subnet 'Subnet.SubnetId' aws ec2 create-subnet --vpc-id "$(sget '.refs.vpc')" --cidr-block 10.0.1.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet subnet)"
mutate igw 'InternetGateway.InternetGatewayId' aws ec2 create-internet-gateway --tag-specifications "$(tags internet-gateway igw)"
mutate - null aws ec2 attach-internet-gateway --internet-gateway-id "$(sget '.refs.igw')" --vpc-id "$(sget '.refs.vpc')"
mutate rt 'RouteTable.RouteTableId' aws ec2 create-route-table --vpc-id "$(sget '.refs.vpc')" --tag-specifications "$(tags route-table rt)"
mutate - null aws ec2 create-route --route-table-id "$(sget '.refs.rt')" --destination-cidr-block 0.0.0.0/0 --gateway-id "$(sget '.refs.igw')"
mutate assoc AssociationId aws ec2 associate-route-table --route-table-id "$(sget '.refs.rt')" --subnet-id "$(sget '.refs.subnet')"
mutate sg GroupId aws ec2 create-security-group --group-name "$(name sg)" --description 'B6-1 Shell web lab' --vpc-id "$(sget '.refs.vpc')" --tag-specifications "$(tags security-group sg)"
old=$SOURCE; source_ip; [ "$SOURCE" = "$old" ] || fail SOURCE_IP_CHANGED
# Raw source address only in this stdin body; never argv, state, log or digest.
INPUT_JSON=$(printf '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]},{"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"%s/32"}]}]' "$SOURCE")
mutate - null aws ec2 authorize-security-group-ingress --group-id "$(sget '.refs.sg')"
INPUT_JSON=
# Query KeyMaterial directly into the exclusive private FD: CLI JSON parsing is in memory.
request null aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 --key-format pem --tag-specifications "$(tags key-pair key)" --dry-run
[ "$API_CODE" = DryRunOperation ] || fail KEY_DRY_RUN_NOT_AUTHORIZED
check_path "$KEY_PATH"
set -C
exec 3> "$KEY_PATH" || fail PRIVATE_FILE_EXISTS_NO_OVERWRITE
set +C
chmod 600 "$KEY_PATH"
write_state '.status="UNKNOWN"|.pending="create-key-pair"'
printf '$ '
printf '%q ' "$AWS_BIN" ec2 create-key-pair --profile "$PROFILE" --region "$REGION" --key-name "$KEY_NAME" --key-type ed25519 --key-format pem --tag-specifications "$(tags key-pair key)" --query KeyMaterial --output text --no-cli-pager
printf '[stdout -> exclusive private FD, withheld]\n'
KEY_MATERIAL=$("$AWS_BIN" ec2 create-key-pair --profile "$PROFILE" --region "$REGION" --key-name "$KEY_NAME" --key-type ed25519 --key-format pem --tag-specifications "$(tags key-pair key)" --query KeyMaterial --output text --no-cli-pager 2>/dev/null)
rc=$?
printf '$ aws ec2 create-key-pair [KeyMaterial -> private memory -> exclusive FD] -> exit %s\n' "$rc"
[ "$rc" = 0 ] && [ -n "$KEY_MATERIAL" ] && [ "$KEY_MATERIAL" != None ] || fail UNKNOWN_KEY_OUTCOME_NO_RECREATE
if ! printf '%s\n' "$KEY_MATERIAL" | dd bs=4096 conv=fsync >&3 2>/dev/null; then
  printf 'KEY_SAVE_BLOCKED material retained in live process memory; no create retry\n'
  while :; do sleep 5; done
fi
exec 3>&-
unset KEY_MATERIAL
[ -s "$KEY_PATH" ] || fail KEY_SAVE_EMPTY_NO_RECREATE
sync || fail KEY_DURABILITY_BLOCKED_NO_RECREATE
request 'KeyPairs[0]' aws ec2 describe-key-pairs --key-names "$KEY_NAME" --include-public-key; okay
KEY_ID=$(printf '%s' "$API_RESULT" | jq -r '.KeyPairId'); fingerprint=$(printf '%s' "$API_RESULT" | jq -r '.KeyFingerprint')
[ "$(printf '%s' "$API_RESULT" | jq -r '.KeyType')" = ed25519 ] || fail KEY_TYPE_MISMATCH
public=$(printf '%s' "$API_RESULT" | jq -r '.PublicKey'); derived=$(ssh-keygen -y -f "$KEY_PATH" 2>/dev/null) || fail KEY_DERIVATION_FAILED
read -r pt pb rest <<< "$public"; read -r dt db rest <<< "$derived"
[ "$pt $pb" = "$dt $db" ] || fail KEY_CORRESPONDENCE_FAILED
unset public derived pt pb dt db
write_state '.refs.key=$id|.key_fingerprint=$fp|.status="WORKING"|del(.pending)' --arg id "$KEY_ID" --arg fp "$fingerprint"
printf 'private_key=RETAINED_0600_IGNORED correspondence=MATCH material=[WITHHELD]\n'
PAYLOAD="$ROOT/runtime/$RUN_ID-launch.json"
check_path "$PAYLOAD"
(umask 077; set -C; jq -nc --arg ami "$AMI" --arg root "$ROOT_DEVICE" --arg key "$KEY_NAME" --arg subnet "$(sget '.refs.subnet')" --arg sg "$(sget '.refs.sg')" --argjson tags "$(tags instance web)" --argjson voltags "$(tags volume web)" '{ImageId:$ami,InstanceType:"t4g.nano",MinCount:1,MaxCount:1,KeyName:$key,CreditSpecification:{CpuCredits:"standard"},MetadataOptions:{HttpTokens:"required",HttpPutResponseHopLimit:1},BlockDeviceMappings:[{DeviceName:$root,Ebs:{VolumeSize:8,VolumeType:"gp3",Encrypted:true,DeleteOnTermination:true}}],NetworkInterfaces:[{DeviceIndex:0,SubnetId:$subnet,Groups:[$sg],AssociatePublicIpAddress:true,DeleteOnTermination:true}],TagSpecifications:($tags+$voltags)}' > "$PAYLOAD") || fail EXCLUSIVE_PAYLOAD_FAILED
seed=$( { jq -cS . "$PAYLOAD"; printf '%s' "$UD_HASH"; } | sha)
token="b6-1-${seed:0:48}"
tmp="$PAYLOAD.tmp.$$"; check_path "$tmp"; (umask 077; set -C; jq --arg token "$token" '.ClientToken=$token' "$PAYLOAD" > "$tmp") || fail EXCLUSIVE_PAYLOAD_TEMP_FAILED
mv "$tmp" "$PAYLOAD"; chmod 600 "$PAYLOAD"; sync
write_state '.client_token=$token|.user_data_hash=$hash' --arg token "$token" --arg hash "$UD_HASH"
request 'Reservations[].Instances[]' aws ec2 describe-instances --filters "Name=tag:RunId,Values=$RUN_ID" Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down; okay
[ "$(printf '%s' "$API_RESULT" | jq length)" = 0 ] || fail INSTANCE_COLLISION
mutate instance 'Instances[0].InstanceId' aws ec2 run-instances --cli-input-json "file://$PAYLOAD" --user-data "file://$USER_DATA"
write_state '.status="ACTIVE"'
printf 'CREATED instance=%s type=t4g.nano bootstrap=PENDING state=%s\n' "$(sget '.refs.instance')" "$STATE"
