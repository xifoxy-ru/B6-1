#!/bin/bash
set +x
. "$(dirname -- "$0")/common.sh"
READ_ONLY_STATUS=true
parse "$@"; identity; load_state
printf 'STATUS run=%s state=%s pending=%s\n' "$RUN_ID" "$(sget '.status')" "$(sget '.pending')"
if [ "$(sget '.status')" = DESTROYED ]; then
  for k in vpc subnet igw rt sg key volume eni; do resource "$k"; ! $PRESENT || fail DESTROYED_RESOURCE_REAPPEARED; printf '%s=EXACT_TYPED_NOT_FOUND\n' "$k"; done
  resource instance
  if $PRESENT; then [ "$(printf '%s' "$OBJ" | jq -r '.State.Name')" = terminated ] && [ "$(printf '%s' "$OBJ" | jq -r '.PublicIpAddress // empty')" = '' ] || fail INSTANCE_STILL_ACTIVE; fi
  printf 'DESTROYED_NOOP verified; local keys/proof RETAINED; endpoint NOT requested\n'; exit 0
fi
case "$SECTION" in all|network|security|compute) ;; *) fail UNKNOWN_SECTION;; esac
if [ "$SECTION" = all ] || [ "$SECTION" = network ]; then
  printf '\n=== NETWORK (actual AWS reads) ===\n'
  for k in vpc subnet rt igw; do resource "$k"; if $PRESENT; then
    case "$k" in
      vpc) printf '%s' "$OBJ" | jq -r '"VPC \(.VpcId) CIDR=\(.CidrBlock) default=\(.IsDefault) state=\(.State)"';;
      subnet) printf '%s' "$OBJ" | jq -r '"SUBNET \(.SubnetId) VPC=\(.VpcId) CIDR=\(.CidrBlock) AZ=\(.AvailabilityZone) state=\(.State) autoIPv4=\(.MapPublicIpOnLaunch)"';;
      rt) printf '%s' "$OBJ" | jq -r '"ROUTE TABLE \(.RouteTableId) VPC=\(.VpcId)", (.Routes[]|"  route \(.DestinationCidrBlock) -> \(.GatewayId) state=\(.State)"),(.Associations[]|"  association \(.RouteTableAssociationId) subnet=\(.SubnetId // "main") main=\(.Main)")';;
      igw) printf '%s' "$OBJ" | jq -r '"IGW \(.InternetGatewayId)",(.Attachments[]|"  attachment VPC=\(.VpcId) state=\(.State)")';;
    esac
  fi; done
fi
if [ "$SECTION" = all ] || [ "$SECTION" = security ]; then
  printf '\n=== SECURITY (source IP always masked) ===\n'
  source_ip; resource sg
  if $PRESENT; then
    rule=$(printf '%s' "$OBJ" | jq -r '.IpPermissions[]|select(.IpProtocol=="tcp" and .FromPort==22 and .ToPort==22)|.IpRanges[].CidrIp')
    [ "$rule" = "$SOURCE/32" ] || fail SSH_SOURCE_CHANGED
    printf '%s' "$OBJ" | jq -e '(.IpPermissions|length)==2 and all(.IpPermissions[]; .IpProtocol=="tcp" and .FromPort==.ToPort and (.IpRanges|length)==1 and ((.Ipv6Ranges//[])|length)==0 and ((.UserIdGroupPairs//[])|length)==0) and any(.IpPermissions[]; .FromPort==80 and .IpRanges[0].CidrIp=="0.0.0.0/0")' >/dev/null || fail EXACT_INGRESS_GUARD
    printf 'SG=%s HTTP=tcp80/0.0.0.0/0 SSH=tcp22/PUBLIC_IPV4_MASKED/32 current_source_match=true\n' "$(sget '.refs.sg')"
    printf '%s' "$OBJ" | jq -e 'any(.IpPermissionsEgress[]; .IpProtocol=="-1" and any(.IpRanges[]; .CidrIp=="0.0.0.0/0"))' >/dev/null || fail OUTBOUND_GUARD
    printf 'Outbound=default_all_IPv4; IAM principal=expected_IAM_user [MASKED_ACCOUNT_ARN]\n'
  fi
fi
if [ "$SECTION" = all ] || [ "$SECTION" = compute ]; then
  printf '\n=== COMPUTE (published server IP allowed) ===\n'
  capture_refs; resource instance
  if $PRESENT; then printf '%s' "$OBJ" | jq -r '"EC2 \(.InstanceId) type=\(.InstanceType) state=\(.State.Name)","  AMI=\(.ImageId) subnet=\(.SubnetId)","  public endpoint=http://\(.PublicIpAddress)/","  IMDSv2=\(.MetadataOptions.HttpTokens) hop=\(.MetadataOptions.HttpPutResponseHopLimit)",(.SecurityGroups[]|"  SG=\(.GroupId)")'; fi
  resource volume; if $PRESENT; then printf '%s' "$OBJ" | jq -r '"ROOT EBS \(.VolumeId) size=\(.Size)GiB type=\(.VolumeType) encrypted=\(.Encrypted) state=\(.State)"'; fi
fi
