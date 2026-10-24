# 실제 정리 결과

**CLEANED — 정확 승인 대상만 확인했다.** 최종 UTC: 2026-10-24T21:04:14.756793+00:00. 계정 전체 자원 부재나 청구 0을 주장하지 않는다. 옛 public IP/HTTP를 다시 요청하지 않았다.

| 대상 | 정확 참조 | 실제 최종 결과 |
|---|---|---|
| EC2 | `i-05b24520155629e9f` | 20:56:31Z terminate 1회 성공 후 terminated |
| Root EBS | `vol-086be86c7d435956a` | 자동 삭제, `InvalidVolume.NotFound` |
| 자동 ENI | `eni-0232a8a788ec49478` | 자동 삭제, `InvalidNetworkInterfaceID.NotFound` |
| 자동 public IPv4 | 이전 `13.124.107.197` | EC2 PublicIpAddress/ENI 연결 제거; EIP ReleaseAddress 호출 없음 |
| custom association | `rtbassoc-04e52ed126ae95029` | non-main 확인 후 disassociate 성공, custom RT 부재 |
| default route / custom RT | `rtb-0b3393b9c2325fdf6` | exact IGW route 삭제·RT 삭제 성공, `InvalidRouteTableID.NotFound` |
| 서브넷 | `subnet-0e41cb6e4d3caab77` | 삭제 성공, `InvalidSubnetID.NotFound` |
| SG | `sg-030553cbc06d587a7` | 삭제 성공, `InvalidGroup.NotFound` |
| IGW | `igw-0d883adc5de5d57a9` | same VPC 분리·삭제 성공, `InvalidInternetGatewayID.NotFound` |
| cloud SSH key | `key-00e758429d0610364` | nonterminated key refs0 후 삭제 성공, `InvalidKeyPair.NotFound` |
| VPC | `vpc-010aff9ac6af6adce` | foreign deps0 재확인·삭제 성공, `InvalidVpcID.NotFound` |
| 로컬 개인키 | `.secrets/b6-1-ssh-key.pem` | **RETAINED**, regular/0600, dir0700, ignored; 내용 출력·복사·hash 없음 |
| 로컬 증빙·소스·Git | 기존 app/deploy/policies/old docs | **RETAINED**, README/이 체크리스트 외 기존 tracked bytes 해시 일치 |

모든 실제 변경은 지원되는 정확 DryRunOperation 뒤 실행했다. 기본 SG/main RT/ACL은 DeleteVpc에 따르며 별도 삭제하지 않았다. detached root fallback/DeleteNetworkInterface/ReleaseAddress는 실행하지 않았다. IAM/예산/연락처/프로필 및 다른 계정/리전 자원은 삭제 대상이 아니며 보존했다.

첫 종료 뒤 정상 상태 전환을 처리하던 빈 assertion 및 key의 실제 typedNotFound 코드 차이로 안전 중단했다. 원 실행/실패를 보존하고 남은 전용 executor를 독립 재검토한 후 진행했으며 terminate/key 삭제를 반복하지 않았다. 자세한 실제 UTC·명령·실패 한계는 [06 TXT](evidence/06-cleanup.txt)와 [JSON](evidence/06-cleanup.json)에 기록했다.

`runtime/cleanup-013-state.json`을 이용한 제품 destroy의 실제 검증은 **DESTROYED_NOOP**, mutation0/옛 endpoint 요청0이다. 새 paid create→destroy roundtrip은 수행하지 않았다.
