# 삭제 체크리스트

**이번 실습 자원은 삭제 완료입니다.** [마지막 삭제 사진](evidence/cleanup/vpc-deleted.png)과 [종료 후 status](evidence/cleanup/final-status.png)에 DESTROYED·pending 없음·8종 정확한 typedNotFound·DESTROYED_NOOP가 남아 있습니다. typedNotFound는 **지정한 자원이 없다는 응답**이며 계정 전체 부재를 뜻하지 않습니다.

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
- [ ] 이번 실습의 최신·최종 청구 확인. 2026년 10월 25일 비용 사진으로 대신하지 않음.

해제된 `3.34.255.78`에는 HTTP·SSH·기타 요청을 다시 하지 않습니다. 정리 완료를 청구 0으로 해석하지 않습니다. [남은 한계](../README.md#limits)


이전 실습의 중복 정리 기록은 Git 이력에 남겨 두었습니다. 계정·예산 설정이나 로컬 개인키는 이번 클라우드 자원 삭제 대상이 아닙니다.
