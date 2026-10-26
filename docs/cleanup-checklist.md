# 실제 정리 결과

## 016 단계별 촬영 — CLEANED

사용자가 `--capture`로 각 삭제 그룹을 촬영하고 Enter로 진행했습니다. [마지막 삭제](evidence/08-guided-capture/08-14-cleanup.png) · [최종 status](evidence/08-guided-capture/08-15-status-destroyed.png)에서 DESTROYED/pending 없음·8종 정확 typedNotFound·DESTROYED_NOOP를 확인했습니다. 아래는 사진/최종 state에서 확인한 참조이며 원본 stdout 재구성은 아닙니다.

| 대상 | 이번 실행의 정확 참조 | 확인 결과 |
|---|---|---|
| vpc | `vpc-0925d98329fe0c841` | 정확한 대상 삭제/typedNotFound |
| subnet | `subnet-0ac93844275b1d4ca` | 정확한 대상 삭제/typedNotFound |
| igw | `igw-0172727a555bc246e` | 정확한 대상 삭제/typedNotFound |
| rt | `rtb-03d022862a6b9bf86` | 정확한 대상 삭제/typedNotFound |
| assoc | `rtbassoc-00f7c9d37bec77bcc` | non-main 연결 해제·RT 삭제 |
| sg | `sg-07bad1fe7d2df086e` | 정확한 대상 삭제/typedNotFound |
| key | `key-0a6c4fa63a19b64da` | 정확한 대상 삭제/typedNotFound |
| instance | `i-02bd9084be1824587` | terminated·공인 IP 연결 제거 |
| volume | `vol-0cd9c4318ee3fae8d` | 정확한 대상 삭제/typedNotFound |
| eni | `eni-091cc09b8e6310358` | 정확한 대상 삭제/typedNotFound |

- [EC2/EBS/ENI 정리 part1](evidence/08-guided-capture/08-10-terminate-part-1.png) · [part2](evidence/08-guided-capture/08-10-terminate-part-2.png) → [RT](evidence/08-guided-capture/08-11-route-cleanup.png) → [subnet/SG](evidence/08-guided-capture/08-12-subnet-sg-cleanup.png) → [IGW/cloud key](evidence/08-guided-capture/08-13-gateway-key-cleanup.png) → VPC 순서였습니다.
- 자동 공인 IPv4 `3.34.255.78` 연결은 제거됐습니다. 해제 주소에 HTTP/SSH/probe하지 않습니다. EBS/ENI는 자동 삭제됐으며 ReleaseAddress·ENI 별도 삭제·root fallback은 이번 관측에서 수행하지 않았습니다.
- 로컬 old/new 키·소스·19장 원본·Git은 보존했습니다. 키는 0600/폴더0700/Git ignored이며 내용·복사·hash는 증빙에 넣지 않았습니다.
- EIP/NAT/ALB/RDS는 이번 실행에서 만들지 않았습니다. default SG/main RT/ACL을 별도로 삭제하지 않았고 다른 계정 자원/IAM/예산/연락처/로그인 설정은 범위 밖입니다.
- 계정 전체 부재나 청구 0을 주장하지 않습니다. 이전 015의 US$0.01 Billing 화면은 당시 관측일 뿐 이번 016의 최신/최종 비용이 아닙니다.

---

# 이전 정리 기록

## 015 Shell replay — CLEANED

최종 UTC **2026-10-25T11:41:32Z**, run `shell-015-20261025`. [실제 cleanup 명령/TXT](evidence/07-shell-replay/07-cleanup.txt)와 [정리 후 status TXT](evidence/07-shell-replay/07-status-destroyed.txt)를 따른다. [native cleanup Terminal PNG](evidence/07-shell-replay/07-cleanup-terminal.png)도 실제 원본을 확인했다.

| 정확 대상 | 참조 | 실제 결과 |
|---|---|---|
| EC2 | `i-0f66d41d8c5b9574b` | terminate1회 뒤 terminated, PublicIpAddress 연결 제거 |
| Root EBS / ENI | `vol-08509c920b0ba55ed` / `eni-08b2a6578c14a31f4` | 자동 삭제, 정확 typedNotFound |
| 자동 public IPv4 | 과거 `43.203.227.198` | 연결 제거, ReleaseAddress·종료후 HTTP 요청 없음 |
| custom association / route table | `rtbassoc-0227cc1567092ab42` / `rtb-0bc981ef48d8710ea` | non-main association·default route·custom RT 삭제, RT typedNotFound |
| Subnet / SG | `subnet-088b99c7fbbb3ec22` / `sg-08d970cf2023c7d11` | 삭제 성공 후 정확 typedNotFound |
| IGW / cloud key | `igw-0cd02ce853e3241d9` / `key-09ac7b8a30c79159d` | detach/delete·nonterminated key refs0 확인 뒤 삭제, typedNotFound |
| VPC | `vpc-09a7b0324655b5ad3` | foreign deps0 확인 뒤 마지막 삭제, typedNotFound |
| 로컬 key·소스·증빙·Git | old key와 `.secrets/key-shell-015-20261025.pem` | 보존, key0600/dir0700/ignored; 내용·복사·hash 없음 |

각 실제 변경 전 지원되는 정확 DryRunOperation을 확인했다. root fallback DeleteVolume·DeleteNetworkInterface·ReleaseAddress는 실행하지 않았다. default SG/main RT/ACL은 VPC 삭제에 따르며 별도로 삭제하지 않았다. IAM/예산/연락처/로그인 설정과 다른 run은 정리 범위 밖으로 보존했다. **계정 전체 부재나 청구 0을 주장하지 않는다.** [Billing 사후 사용자 마스킹 화면](evidence/07-shell-replay/07-billing.png)은 10월·필터0·US$0.01의 조회 당시 표시만 확인하며, 갱신 시각/최종청구/이번 run 단독 비용/credit 적용은 증명하지 않는다. 새 생성을 위해서는 새 run/state가 필요하며 이번 DESTROYED state/옛 endpoint를 재사용하지 않는다.

---

# 이전 013 정리 결과 — 역사 자료

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
