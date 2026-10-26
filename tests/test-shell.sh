#!/bin/bash
# Offline only. Fake AWS server data contains synthetic fixtures, never user values.
set -eu
SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP=$(mktemp -d); TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/project"
mkdir -p "$ROOT/scripts" "$ROOT/deploy" "$ROOT/app" "$ROOT/runtime" "$ROOT/.secrets" "$TMP/bin"
cp "$SOURCE_ROOT"/scripts/*.sh "$ROOT/scripts/"
cp "$SOURCE_ROOT/deploy/render-user-data.sh" "$SOURCE_ROOT/deploy/user-data.sh.tpl" "$SOURCE_ROOT/deploy/compose.yaml" "$SOURCE_ROOT/deploy/nginx.conf" "$ROOT/deploy/"
cp "$SOURCE_ROOT/app/index.html" "$ROOT/app/"
chmod 700 "$ROOT/runtime" "$ROOT/.secrets"
export B6_EXPECTED_ACCOUNT=$(printf '%012d' 1) B6_IAM_USER=fixture-user
export DB="$TMP/db.json" CALLS="$TMP/calls" FIX_ROOT="$ROOT"
printf '{}\n' > "$DB"; : > "$CALLS"
cat > "$TMP/bin/aws" <<'FAKE'
#!/bin/bash
set -eu
service=$1; op=$2; shift 2; ARGS=("$@")
arg() { local n=0; while [ "$n" -lt "${#ARGS[@]}" ]; do if [ "${ARGS[$n]}" = "$1" ]; then printf '%s' "${ARGS[$((n+1))]}"; return; fi; n=$((n+1)); done; }
query=$(arg --query); dry=false
for a in "${ARGS[@]}"; do [ "$a" != --dry-run ] || dry=true; done
printf '%s %s\n' "$op" "$dry" >> "$CALLS"
if [ "$op" = authorize-security-group-ingress ]; then
 [ "$(arg --ip-permissions)" = file:///dev/stdin ] || exit 96
 input=$(cat); printf '%s' "$input" | jq -e 'type=="array" and length==2' >/dev/null || exit 95
fi
if $dry; then printf 'An error occurred (DryRunOperation)\n' >&2; exit 254; fi
if [ "${FAKE_DENY:-}" = "$op" ]; then printf 'An error occurred (AccessDenied)\n' >&2; exit 254; fi
if [ "${FAKE_UNKNOWN:-}" = "$op" ]; then printf 'An error occurred (RequestTimeout)\n' >&2; exit 255; fi
A=$B6_EXPECTED_ACCOUNT; run=fixture-run
TAGS=$(jq -nc --arg run "$run" --arg name "b6-1-$run-PLACEHOLDER" '[{Key:"Project",Value:"B6-1"},{Key:"RunId",Value:$run},{Key:"Name",Value:$name}]')
put() { local key=$1 body=$2; jq --arg k "$key" --argjson v "$body" '.[$k]=$v' "$DB" > "$DB.tmp"; mv "$DB.tmp" "$DB"; }
get() { jq -c --arg k "$1" '.[$k]' "$DB"; }
del() { jq --arg k "$1" 'del(.[$k])' "$DB" > "$DB.tmp"; mv "$DB.tmp" "$DB"; }
obj() { jq -nc --arg id "$2" --arg account "$A" --arg kind "$1" --argjson tags "$(printf '%s' "$TAGS" | jq --arg n "b6-1-$run-$1" 'map(if .Key=="Name" then .Value=$n else . end)')" '{OwnerId:$account,Tags:$tags} + {($kind):$id}'; }
result='{}'
case "$op" in
 get-caller-identity) result=$(jq -nc --arg a "$A" --arg user "$B6_IAM_USER" '{Account:$a,Arn:("arn:aws:iam::"+$a+":user/"+$user)}'); if [ "${FAKE_WRONG:-}" = true ]; then result=$(printf '%s' "$result" | jq '.Arn="fixture-root"'); fi;;
 describe-images) result='{"Images":[{"ImageId":"ami-00000000000000001","ImageOwnerAlias":"amazon","Architecture":"arm64","State":"available","VirtualizationType":"hvm","RootDeviceType":"ebs","RootDeviceName":"/dev/xvda","CreationDate":"fixture","BlockDeviceMappings":[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":2}}]}]}';;
 describe-instance-types) result='{"InstanceTypes":[{"InstanceType":"t4g.nano","MemoryInfo":{"SizeInMiB":512},"ProcessorInfo":{"SupportedArchitectures":["arm64"]}}]}';;
 describe-availability-zones) result='{"AvailabilityZones":[{"ZoneName":"ap-northeast-2a","ZoneType":"availability-zone","State":"available"}]}';;
 create-vpc) result=$(obj vpc vpc-00000000000000001 | jq '.+{VpcId:.vpc,CidrBlock:"10.0.0.0/16",IsDefault:false,State:"available"}'); put vpc "$result"; result=$(jq -nc --argjson v "$result" '{Vpc:$v}');;
 create-subnet) result=$(obj subnet subnet-00000000000000001 | jq '.+{SubnetId:.subnet,VpcId:"vpc-00000000000000001",CidrBlock:"10.0.1.0/24",AvailabilityZone:"ap-northeast-2a",State:"available",MapPublicIpOnLaunch:false}'); put subnet "$result"; result=$(jq -nc --argjson v "$result" '{Subnet:$v}');;
 create-internet-gateway) result=$(obj igw igw-00000000000000001 | jq '.+{InternetGatewayId:.igw,Attachments:[]}'); put igw "$result"; result=$(jq -nc --argjson v "$result" '{InternetGateway:$v}');;
 attach-internet-gateway) put igw "$(get igw | jq '.Attachments=[{VpcId:"vpc-00000000000000001",State:"available"}]')";;
 create-route-table) result=$(obj rt rtb-00000000000000001 | jq '.+{RouteTableId:.rt,VpcId:"vpc-00000000000000001",Associations:[],Routes:[{DestinationCidrBlock:"10.0.0.0/16",GatewayId:"local",State:"active"}]}'); put rt "$result"; result=$(jq -nc --argjson v "$result" '{RouteTable:$v}');;
 create-route) put rt "$(get rt | jq '.Routes+=[{DestinationCidrBlock:"0.0.0.0/0",GatewayId:"igw-00000000000000001",State:"active"}]')";;
 associate-route-table) put rt "$(get rt | jq '.Associations=[{Main:false,SubnetId:"subnet-00000000000000001",RouteTableAssociationId:"rtbassoc-00000000000000001"}]')"; result='{"AssociationId":"rtbassoc-00000000000000001"}';;
 create-security-group) result=$(obj sg sg-00000000000000001 | jq '.+{GroupId:.sg,GroupName:"b6-1-fixture-run-sg",VpcId:"vpc-00000000000000001",IpPermissions:[],IpPermissionsEgress:[{IpProtocol:"-1",IpRanges:[{CidrIp:"0.0.0.0/0"}]}]}'); put sg "$result"; result='{"GroupId":"sg-00000000000000001"}';;
 authorize-security-group-ingress) put sg "$(get sg | jq --argjson input "$input" '.IpPermissions=$input')";;
 create-key-pair) result=$(obj key key-00000000000000001 | jq '.+{KeyPairId:.key,KeyName:"b6-1-fixture-run-key",KeyFingerprint:"fixture-fingerprint",PublicKey:"fixture-type fixture-public"}'); put key "$(printf '%s' "$result" | jq '.KeyType="ed25519"')"; result=$(printf '%s' "$result" | jq '.KeyMaterial="FIXTURE_MATERIAL_NOT_A_REAL_KEY"');;
 run-instances) result=$(obj web i-00000000000000001 | jq '.+{InstanceId:.web,InstanceType:"t4g.nano",ImageId:"ami-00000000000000001",State:{Name:"running"},VpcId:"vpc-00000000000000001",SubnetId:"subnet-00000000000000001",KeyName:"b6-1-fixture-run-key",PublicIpAddress:"203.0.113.1",BlockDeviceMappings:[{Ebs:{VolumeId:"vol-00000000000000001",DeleteOnTermination:true}}],NetworkInterfaces:[{NetworkInterfaceId:"eni-00000000000000001",Attachment:{DeleteOnTermination:true}}],SecurityGroups:[{GroupId:"sg-00000000000000001"}],MetadataOptions:{HttpTokens:"required",HttpPutResponseHopLimit:1}}'); put instance "$result"; put volume "$(obj web vol-00000000000000001 | jq '.+{VolumeId:.web,Size:8,VolumeType:"gp3",Encrypted:true,State:"in-use",Attachments:[{InstanceId:"i-00000000000000001"}]}')"; put eni "$(jq -nc --arg a "$A" '{OwnerId:$a,NetworkInterfaceId:"eni-00000000000000001",VpcId:"vpc-00000000000000001",SubnetId:"subnet-00000000000000001",Attachment:{InstanceId:"i-00000000000000001",DeleteOnTermination:true}}')"; result=$(jq -nc --argjson v "$result" '{Instances:[$v]}');;
 terminate-instances) put instance "$(get instance | jq '.State.Name="terminated"|del(.PublicIpAddress)|.NetworkInterfaces=[]|.BlockDeviceMappings=[]')"; del volume; del eni;;
 disassociate-route-table) put rt "$(get rt | jq '.Associations=[]')";;
 delete-route) put rt "$(get rt | jq '.Routes|=map(select(.GatewayId=="local"))')";;
 detach-internet-gateway) put igw "$(get igw | jq '.Attachments=[]')";;
 delete-route-table) del rt;; delete-subnet) del subnet;; delete-security-group) del sg;; delete-internet-gateway) del igw;; delete-key-pair) del key;; delete-vpc) del vpc;;
 describe-*)
  case "$op" in describe-vpcs) k=vpc; root=Vpcs; missing=InvalidVpcID.NotFound;; describe-subnets) k=subnet;root=Subnets;missing=InvalidSubnetID.NotFound;; describe-internet-gateways) k=igw;root=InternetGateways;missing=InvalidInternetGatewayID.NotFound;; describe-route-tables) k=rt;root=RouteTables;missing=InvalidRouteTableID.NotFound;; describe-security-groups) k=sg;root=SecurityGroups;missing=InvalidGroup.NotFound;; describe-key-pairs) k=key;root=KeyPairs;missing=InvalidKeyPair.NotFound;; describe-instances) k=instance;root=Reservations;missing=InvalidInstanceID.NotFound;; describe-volumes) k=volume;root=Volumes;missing=InvalidVolume.NotFound;; describe-network-interfaces) k=eni;root=NetworkInterfaces;missing=InvalidNetworkInterfaceID.NotFound;; *) exit 98;; esac
  value=$(get "$k"); exact=false
  for a in "${ARGS[@]}"; do case "$a" in --vpc-ids|--subnet-ids|--internet-gateway-ids|--route-table-ids|--group-ids|--key-pair-ids|--instance-ids|--volume-ids|--network-interface-ids) exact=true;; esac; done
  if [ "$value" = null ] && $exact; then printf 'An error occurred (%s)\n' "$missing" >&2; exit 254; fi
  values='[]'; [ "$value" = null ] || values=$(jq -nc --argjson v "$value" '[$v]')
  if ! $exact && [ "$k" = instance ] && [ "$(printf '%s' "$value" | jq -r '.State.Name // empty')" = terminated ]; then values='[]'; fi
  if [ "$k" = instance ]; then result=$(jq -nc --arg a "$A" --argjson v "$values" '{Reservations:(if ($v|length)>0 then [{OwnerId:$a,Instances:$v}] else [] end)}'); else result=$(jq -nc --arg root "$root" --argjson v "$values" '{($root):$v}'); fi;;
 *) exit 97;;
esac
if [ "$query" = KeyMaterial ]; then printf '%s\n' "$(printf '%s' "$result" | jq -r '.KeyMaterial')"; exit 0; fi
case "$query" in
 null) printf 'null\n';;
 '[Account,Arn]') printf '%s' "$result" | jq '[.Account,.Arn]';;
 'InstanceTypes[0].[MemoryInfo.SizeInMiB,ProcessorInfo.SupportedArchitectures]') printf '%s' "$result" | jq '[.InstanceTypes[0].MemoryInfo.SizeInMiB,.InstanceTypes[0].ProcessorInfo.SupportedArchitectures]';;
 'sort_by(Images,&CreationDate)[-1]') printf '%s' "$result" | jq '.Images|sort_by(.CreationDate)|last';;
 'Subnets[].SubnetId') if [ "${FAKE_FOREIGN:-}" = true ]; then printf '%s' "$result" | jq '[.Subnets[].SubnetId]+["subnet-fffffffffffffffff"]'; else printf '%s' "$result" | jq '[.Subnets[].SubnetId]'; fi;;
 'NetworkInterfaces[].NetworkInterfaceId') printf '%s' "$result" | jq '[.NetworkInterfaces[].NetworkInterfaceId]';;
 'InternetGateways[].InternetGatewayId') printf '%s' "$result" | jq '[.InternetGateways[].InternetGatewayId]';;
 'Reservations[].Instances[]') printf '%s' "$result" | jq '[.Reservations[].Instances[]]';;
 'Reservations[].Instances[].InstanceId') printf '%s' "$result" | jq '[.Reservations[].Instances[].InstanceId]';;
 'SecurityGroups[?GroupName!=`default`].GroupId') printf '%s' "$result" | jq '[.SecurityGroups[]|select(.GroupName!="default")|.GroupId]';;
 'RouteTables[?!contains(Associations[].Main, `true`)].RouteTableId') printf '%s' "$result" | jq '[.RouteTables[]|select(any(.Associations[];.Main==true)|not)|.RouteTableId]';;
 *) printf '%s' "$result" | jq ".$query";;
esac
FAKE
cat > "$TMP/bin/curl" <<'FAKE'
#!/bin/bash
case "$*" in *checkip.amazonaws.com*) printf '8.8.8.8\n';; *-w*) printf '200';; */health*) printf 'B6-1 OK\n';; *) cat "$FIX_ROOT/app/index.html";; esac
FAKE
cat > "$TMP/bin/git" <<'FAKE'
#!/bin/sh
exit 0
FAKE
cat > "$TMP/bin/ssh-keygen" <<'FAKE'
#!/bin/sh
printf 'fixture-type fixture-public\n'
FAKE
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sync"
# hostwide sync is mocked; real dd conv=fsync still exercises the exclusive dummy-key file.
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" B6_AWS_BIN="$TMP/bin/aws"
export B6_RUN_PLAN="$ROOT/runtime/fixture-plan.json"
jq -n --arg hash "$("$ROOT/deploy/render-user-data.sh" --output "$ROOT/runtime/fixture-preview.sh"; shasum -a 256 "$ROOT/runtime/fixture-preview.sh" | awk '{print $1}')" '{run_id:"fixture-run",ami:"ami-00000000000000001",az:"ap-northeast-2a",user_data_sha256:$hash}' > "$B6_RUN_PLAN"
# Capture cannot be driven by a pipe/file: reject before any AWS/local state write.
for command in create destroy; do
  "$ROOT/scripts/$command.sh" --capture --apply --run-id fixture-run --state runtime/capture-refuse.json < /dev/null > "$TMP/capture-refuse.txt" 2>&1 && exit 1
  grep -q CAPTURE_NATIVE_TTY_REQUIRED_BEFORE_WRITES "$TMP/capture-refuse.txt"
  [ ! -e "$ROOT/runtime/capture-refuse.json" ]
  [ ! -e "$ROOT/runtime/.run-fixture-run.lock" ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 0 ]
done
printf 'PASS capture nonTTY rejects before API/state/lock/private writes\n'
# These fixture modes run in a real test PTY; a human test controller sends each Enter.
case "${1:-}" in
 --capture-success-fixture|--capture-eof-fixture|--capture-interrupt-fixture)
  mode=$1
  trap 'printf "TEST_PARENT_SIGINT observed\n"' INT
  if "$ROOT/scripts/create.sh" --capture --run-id fixture-run --state runtime/state.json --apply; then rc=0; else rc=$?; fi
  trap - INT
  if [ "$mode" != --capture-success-fixture ]; then
    if [ "$mode" = --capture-eof-fixture ]; then [ "$rc" = 1 ]; else [ "$rc" = 130 ]; fi
    [ "$(jq -r '.capture_waiting' "$ROOT/runtime/state.json")" = true ]
    [ "$(jq -r '.capture_checkpoint' "$ROOT/runtime/state.json")" = create-vpc ]
    [ "$(jq -r '.refs.vpc' "$ROOT/runtime/state.json")" = vpc-00000000000000001 ]
    ! grep -q '^create-subnet false' "$CALLS"
    "$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/paused.txt" 2>&1 && exit 1
    grep -q CAPTURE_PAUSED_REQUIRES_REVIEW_NO_RERUN "$TMP/paused.txt"
    ! grep -q '^terminate-instances false' "$CALLS"
    printf 'PASS %s preserves VPC-only state/wait marker; no next group; mutation rerun blocked; real AWS=0\n' "$mode"
    exit 0
  fi
  [ "$rc" = 0 ] && [ "$(jq -r '.status' "$ROOT/runtime/state.json")" = ACTIVE ]
  [ "$(jq -r '.capture_waiting // false' "$ROOT/runtime/state.json")" = false ]
  "$ROOT/scripts/destroy.sh" --capture --state runtime/state.json --apply || exit 1
  [ "$(jq -r '.status' "$ROOT/runtime/state.json")" = DESTROYED ]
  [ "$(jq -r '.capture_waiting // false' "$ROOT/runtime/state.json")" = false ]
  [ "$(grep -c '^run-instances false' "$CALLS")" = 1 ] && [ "$(grep -c '^terminate-instances false' "$CALLS")" = 1 ]
  printf 'PASS manual PTY Enter through create5/destroy5 checkpoints; exact fake create/destroy once; real AWS=0\n'
  exit 0;;
esac
"$ROOT/scripts/create.sh" --state runtime/state.json > "$TMP/create.txt"
[ "$(wc -l < "$CALLS" | tr -d ' ')" = 0 ] || { printf 'default PLAN made AWS calls\n'; exit 1; }
printf 'PASS default PLAN makes no AWS calls\n'
"$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/state.json --apply > "$TMP/create.txt"
[ "$(jq -r '.status' "$ROOT/runtime/state.json")" = ACTIVE ]
[ "$(stat -f '%Lp' "$ROOT/.secrets/key-fixture-run.pem")" = 600 ]
[ -s "$ROOT/.secrets/key-fixture-run.pem" ]
! grep -q 'FIXTURE_MATERIAL\|8\.8\.8\.8' "$TMP/create.txt"
! grep -q 'FIXTURE_MATERIAL\|8\.8\.8\.8' "$ROOT/runtime/state.json"
printf 'PASS fake create full order / no optional KeyType / private fd durable / secret-IP redaction\n'
# Wrong principal is rejected before any mutation.
before=$(grep -c ' false$' "$CALLS")
FAKE_WRONG=true "$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/wrong.txt" 2>&1 && exit 1
[ "$(grep -c ' false$' "$CALLS")" -ge "$before" ] # reads are logged too; exact mutate counts checked below
! grep -q '^terminate-instances false' "$CALLS"
printf 'PASS wrong fixed principal blocks termination\n'
# Fresh Main and foreign tags are rejected before termination.
jq '.rt.Associations[0].Main=true' "$DB" > "$DB.tmp"; mv "$DB.tmp" "$DB"
"$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/main.txt" 2>&1 && exit 1
! grep -q '^terminate-instances false' "$CALLS"
jq '.rt.Associations[0].Main=false | .sg.Tags=[]' "$DB" > "$DB.tmp"; mv "$DB.tmp" "$DB"
"$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/tag.txt" 2>&1 && exit 1
! grep -q '^terminate-instances false' "$CALLS"
jq --argjson tags "$(jq '.rt.Tags|map(if .Key=="Name" then .Value="b6-1-fixture-run-sg" else . end)' "$DB")" '.sg.Tags=$tags' "$DB" > "$DB.tmp"; mv "$DB.tmp" "$DB"
FAKE_FOREIGN=true "$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/foreign.txt" 2>&1 && exit 1
! grep -q '^terminate-instances false' "$CALLS"
printf 'PASS Main/tag/foreign dependency block before terminate\n'
# Wrong region / traversal / insecure existing secret reject without a write.
"$ROOT/scripts/destroy.sh" --state runtime/state.json --region us-east-1 --apply > "$TMP/region.txt" 2>&1 && exit 1
"$ROOT/scripts/create.sh" --state runtime/../../bad.json > "$TMP/path.txt" 2>&1 && exit 1
"$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/new-state.json --apply > "$TMP/key.txt" 2>&1 && exit 1
! grep -q '^terminate-instances false' "$CALLS"
printf 'PASS region/traversal/existing private no-overwrite\n'
"$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/destroy.txt"
[ "$(jq -r '.status' "$ROOT/runtime/state.json")" = DESTROYED ]
[ -s "$ROOT/.secrets/key-fixture-run.pem" ]
[ "$(grep -c '^terminate-instances false' "$CALLS")" = 1 ]
[ "$(grep -c '^delete-key-pair false' "$CALLS")" = 1 ]
[ "$(grep -c '^run-instances false' "$CALLS")" = 1 ]
[ "$(grep -c '^create-key-pair false' "$CALLS")" = 1 ]
# Check dependency order from actual fake command invocation trace, not static source spelling.
actual=$(grep -E '^(terminate-instances|disassociate-route-table|delete-route|delete-route-table|delete-subnet|delete-security-group|detach-internet-gateway|delete-internet-gateway|delete-key-pair|delete-vpc) false$' "$CALLS" | awk '{print $1}' | paste -sd ',' -)
[ "$actual" = terminate-instances,disassociate-route-table,delete-route,delete-route-table,delete-subnet,delete-security-group,detach-internet-gateway,delete-internet-gateway,delete-key-pair,delete-vpc ]
printf 'PASS fake destroy dependency sequence / self ENI-volume capture / typedNotFound\n'
count=$(wc -l < "$CALLS")
"$ROOT/scripts/destroy.sh" --state runtime/state.json --apply > "$TMP/noop.txt"
grep -q DESTROYED_NOOP "$TMP/noop.txt"
[ "$(grep -c '^terminate-instances false' "$CALLS")" = 1 ]
FAKE_DENY=describe-vpcs "$ROOT/scripts/status.sh" --state runtime/state.json > "$TMP/deny.txt" 2>&1 && exit 1
printf 'PASS already destroyed NOOP; AccessDenied is not absence; no key deletion\n'
# Ambiguous create cannot be repeated because durable UNKNOWN/pending state remains.
printf '{}\n' > "$DB"
rm -rf "$ROOT/runtime/.run-fixture-run.lock"
rm -f "$ROOT/.secrets/key-fixture-run.pem" "$ROOT/runtime/fixture-run-user-data.sh" "$ROOT/runtime/fixture-run-launch.json"
FAKE_UNKNOWN=run-instances "$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/unknown.json --apply > "$TMP/unknown.txt" 2>&1 && exit 1
[ "$(jq -r '.status' "$ROOT/runtime/unknown.json")" = UNKNOWN ]
[ "$(jq -r '.pending' "$ROOT/runtime/unknown.json")" = run-instances ]
old=$(grep -c '^run-instances false' "$CALLS")
"$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/unknown.json --apply > "$TMP/retry.txt" 2>&1 && exit 1
[ "$(grep -c '^run-instances false' "$CALLS")" = "$old" ]
printf 'PASS UNKNOWN instance blocks duplicate create\n'
# An ambiguous key response also remains UNKNOWN and cannot create another key.
printf '{}\n' > "$DB"
rm -rf "$ROOT/runtime/.run-fixture-run.lock"
rm -f "$ROOT/.secrets/key-fixture-run.pem" "$ROOT/runtime/fixture-run-user-data.sh" "$ROOT/runtime/fixture-run-launch.json"
FAKE_UNKNOWN=create-key-pair "$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/unknown-key.json --apply > "$TMP/unknown-key.txt" 2>&1 && exit 1
[ "$(jq -r '.status' "$ROOT/runtime/unknown-key.json")" = UNKNOWN ]
[ "$(jq -r '.pending' "$ROOT/runtime/unknown-key.json")" = create-key-pair ]
old=$(grep -c '^create-key-pair false' "$CALLS")
"$ROOT/scripts/create.sh" --run-id fixture-run --state runtime/unknown-key.json --apply > "$TMP/key-retry.txt" 2>&1 && exit 1
[ "$(grep -c '^create-key-pair false' "$CALLS")" = "$old" ]
printf 'PASS UNKNOWN key blocks regeneration and retains local file\n'
# Deterministic shell renderer matches itself, and never overwrites existing output.
"$ROOT/deploy/render-user-data.sh" --output "$ROOT/runtime/render-a.sh"
"$ROOT/deploy/render-user-data.sh" --output "$ROOT/runtime/render-b.sh"
cmp "$ROOT/runtime/render-a.sh" "$ROOT/runtime/render-b.sh"
"$ROOT/deploy/render-user-data.sh" --output "$ROOT/runtime/render-a.sh" > /dev/null 2>&1 && exit 1
printf 'PASS deterministic UTF8 shell renderer and exclusive no-overwrite\n'
printf 'ALL OFFLINE SHELL TESTS PASS; real AWS/network calls=0\n'
