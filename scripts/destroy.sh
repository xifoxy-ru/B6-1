#!/bin/bash
set +x
. "$(dirname -- "$0")/common.sh"
parse "$@"
$APPLY || { plan destroy; exit 0; }
identity; load_state
if [ "$(sget '.status')" = DESTROYED ]; then
  exec "$ROOT/scripts/status.sh" --state "$STATE" --profile "$PROFILE" --region "$REGION"
fi
# Complete fresh preflight BEFORE terminating anything, including Main/tag/foreign checks.
for k in vpc subnet igw rt sg key; do resource "$k"; done
capture_refs
foreign_guard
resource instance
if $PRESENT && [ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" != terminated ]; then
  mutate - null aws ec2 terminate-instances --instance-ids "$(sget '.refs.instance')"
fi
for n in $(seq 1 24); do
  resource instance
  if ! $PRESENT || [ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" = terminated ]; then break; fi
  sleep 5
done
if $PRESENT; then
  [ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" = terminated ] || fail TERMINATION_PENDING
  [ -z "$(printf '%s' "$OBJ" | jq -r '.PublicIpAddress // empty')" ] || fail PUBLIC_ASSOCIATION_PENDING
fi
printf 'instance=TERMINATED public_ipv4_association=REMOVED (no endpoint request)\n'
for k in volume eni; do
  requested=false
  for n in $(seq 1 18); do
    resource "$k"; $PRESENT || break
    if [ "$k" = volume ] && ! $requested; then
      if printf '%s' "$OBJ" | jq -e '.State=="available" and (.Attachments|length)==0 and .Size==8 and .Encrypted and .VolumeType=="gp3"' >/dev/null; then
        mutate - null aws ec2 delete-volume --volume-id "$(sget '.refs.volume')"
        requested=true
      fi
    fi
    sleep 5
  done
  ! $PRESENT || fail COST_RESOURCE_REMAINS_NO_BLIND_DELETE
  printf '%s=EXACT_TYPED_NOT_FOUND\n' "$k"
done
resource rt
if $PRESENT; then
  associations=$(printf '%s' "$OBJ" | jq -c '.Associations')
  printf '%s' "$associations" | jq -e --arg assoc "$(sget '.refs.assoc')" --arg subnet "$(sget '.refs.subnet')" 'all(.[]; .Main!=true and .RouteTableAssociationId==$assoc and .SubnetId==$subnet)' >/dev/null || fail FOREIGN_ASSOCIATION
  if [ "$(printf '%s' "$associations" | jq length)" != 0 ]; then mutate - null aws ec2 disassociate-route-table --association-id "$(sget '.refs.assoc')"; fi
  resource rt
  routes=$(printf '%s' "$OBJ" | jq -c '[.Routes[]|select(.GatewayId!="local")]')
  printf '%s' "$routes" | jq -e --arg igw "$(sget '.refs.igw')" 'all(.[]; .DestinationCidrBlock=="0.0.0.0/0" and .GatewayId==$igw)' >/dev/null || fail FOREIGN_ROUTE
  if [ "$(printf '%s' "$routes" | jq length)" != 0 ]; then mutate - null aws ec2 delete-route --route-table-id "$(sget '.refs.rt')" --destination-cidr-block 0.0.0.0/0; fi
  resource rt
  printf '%s' "$OBJ" | jq -e '(.Associations|length)==0 and all(.Routes[]; .GatewayId=="local")' >/dev/null || fail RT_STILL_USED
  mutate - null aws ec2 delete-route-table --route-table-id "$(sget '.refs.rt')"
fi
resource subnet
if $PRESENT; then foreign_guard; mutate - null aws ec2 delete-subnet --subnet-id "$(sget '.refs.subnet')"; fi
resource sg
if $PRESENT; then foreign_guard; mutate - null aws ec2 delete-security-group --group-id "$(sget '.refs.sg')"; fi
resource igw
if $PRESENT; then
  printf '%s' "$OBJ" | jq -e --arg vpc "$(sget '.refs.vpc')" 'all(.Attachments[]; .VpcId==$vpc)' >/dev/null || fail IGW_FOREIGN_ATTACHMENT
  if [ "$(printf '%s' "$OBJ" | jq '.Attachments|length')" != 0 ]; then mutate - null aws ec2 detach-internet-gateway --internet-gateway-id "$(sget '.refs.igw')" --vpc-id "$(sget '.refs.vpc')"; fi
  resource igw
  [ "$(printf '%s' "$OBJ" | jq '.Attachments|length')" = 0 ] || fail IGW_STILL_ATTACHED
  mutate - null aws ec2 delete-internet-gateway --internet-gateway-id "$(sget '.refs.igw')"
fi
resource key
if $PRESENT; then
  request 'Reservations[].Instances[].InstanceId' aws ec2 describe-instances --filters "Name=key-name,Values=$(sget '.key_name')" Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down; okay
  [ "$(printf '%s' "$API_RESULT" | jq length)" = 0 ] || fail KEY_STILL_REFERENCED
  mutate - null aws ec2 delete-key-pair --key-pair-id "$(sget '.refs.key')"
fi
resource vpc
if $PRESENT; then
  foreign_guard
  for k in subnet sg rt eni igw; do resource "$k"; ! $PRESENT || fail VPC_DEPENDENCY_REMAINS; done
  mutate - null aws ec2 delete-vpc --vpc-id "$(sget '.refs.vpc')"
fi
for k in vpc subnet igw rt sg key volume eni; do
  resource "$k"; ! $PRESENT || fail DELETE_PENDING_TYPED_ABSENCE_NOT_CONFIRMED
  printf '%s=EXACT_TYPED_NOT_FOUND\n' "$k"
done
write_state '.status="DESTROYED"|del(.pending,.public_endpoint)'
printf 'CLEANED exact_run=%s local_old_and_new_keys=RETAINED proof=RETAINED no_global_billzero_claim\n' "$RUN_ID"
