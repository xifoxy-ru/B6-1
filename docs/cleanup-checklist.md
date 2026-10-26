# 삭제 체크리스트

**016 실습은 CLEANED입니다.** [마지막 삭제 사진](evidence/08-guided-capture/08-14-cleanup.png)과 [종료 후 status](evidence/08-guided-capture/08-15-status-destroyed.png)에 DESTROYED·pending 없음·8종 정확한 typedNotFound·DESTROYED_NOOP가 남아 있습니다. typedNotFound는 **지정한 자원이 없다는 응답**이며 계정 전체 부재를 뜻하지 않습니다.

## 이번 실습의 정확한 대상

| 대상 | 참조 | 확인 결과 |
|---|---|---|
| EC2 | `i-02bd9084be1824587` | terminated·공인 IP 연결 제거 |
| Root EBS | `vol-0cd9c4318ee3fae8d` | 자동 삭제·typedNotFound |
| 자동 ENI | `eni-091cc09b8e6310358` | 자동 삭제·typedNotFound |
| RT 연결 | `rtbassoc-00f7c9d37bec77bcc` | non-main 연결 해제·RT 삭제 |
| custom RT | `rtb-03d022862a6b9bf86` | 기본 IGW 경로·RT 삭제·typedNotFound |
| Subnet | `subnet-0ac93844275b1d4ca` | 삭제·typedNotFound |
| SG | `sg-07bad1fe7d2df086e` | 삭제·typedNotFound |
| IGW | `igw-0172727a555bc246e` | VPC에서 분리·삭제·typedNotFound |
| cloud key | `key-0a6c4fa63a19b64da` | 사용 중인 인스턴스 참조 없음 확인 후 삭제·typedNotFound |
| VPC | `vpc-0925d98329fe0c841` | 마지막 삭제·typedNotFound |

- [x] EC2 종료 후 EBS·ENI·자동 공인 IP 연결 제거 확인. 별도 ReleaseAddress·ENI 삭제·root fallback은 이번 실행에서 사용하지 않음.
- [x] RT → subnet/SG → IGW/cloud key → VPC 순서로 정리. [단계별 사진](evidence-guide.md#current-captures)
- [x] 로컬 old/new 키·소스·사진·Git 보존. 키 0600·폴더0700·Git 제외, 내용·복사·hash 없음.
- [x] EIP/NAT/ALB/RDS는 이번 실행에서 만들지 않음. 계정 전체에 없다는 뜻은 아님.
- [x] default SG/main RT/ACL은 따로 삭제하지 않음. 다른 계정 자원·IAM·예산·연락처·로그인 설정은 범위 밖.
- [ ] 이번 016의 최신·최종 청구 확인. 이전 015 비용 사진으로 대신하지 않음.

해제된 `3.34.255.78`에는 HTTP·SSH·기타 요청을 다시 하지 않습니다. 정리 완료를 청구 0으로 해석하지 않습니다. [남은 한계](../README.md#limits)

## 과거 정리 기록

| 실습 | 당시 결과·원본 |
|---|---|
| 015 | `shell-015-20261025` CLEANED, 2026-10-25T11:41:32Z. [cleanup TXT](evidence/07-shell-replay/07-cleanup.txt) · [status TXT](evidence/07-shell-replay/07-status-destroyed.txt) · [사진](evidence/07-shell-replay/07-cleanup-terminal.png) |
| 013 | 당시 승인된 012 자원 CLEANED, 2026-10-24T21:04:14.756793+00:00. [06 TXT](evidence/06-cleanup.txt) · [06 JSON](evidence/06-cleanup.json) |

과거의 정확한 대상 번호·명령·중단/재개 기록은 위 원본에 남겨 두었습니다. `13.124.107.197`·`43.203.227.198`도 해제된 주소입니다. 반복되던 과거 대상 표를 여기서 제거했지만 원본 PNG/TXT/JSON은 변경하지 않았습니다. 당시 문제는 [트러블슈팅의 과거 기록](troubleshooting.md#history)에서 찾습니다.
