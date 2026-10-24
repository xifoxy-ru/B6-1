# 정리 체크리스트

상태: **PENDING — 아직 삭제하지 않았다.** 실제 삭제는 별도 사용자 승인 후 수행하고, 각 결과를 아래에 추가해야 한다. 현재 자원을 유지하는 동안 비용이 발생할 수 있다.

| 대상 | 실제 참조 | 상태 / 정리 후 필요한 증빙 |
|---|---|---|
| EC2 | `i-05b24520155629e9f` | PENDING; 종료 상태 조회 |
| Root EBS | `vol-086be86c7d435956a` (8 GiB encrypted gp3, DeleteOnTermination=true) | PENDING; EC2 종료 뒤 실제 삭제 여부 조회 |
| 자동 ENI | `eni-0232a8a788ec49478` | PENDING; EC2 종료 뒤 남은 ENI 여부 조회 |
| 자동 public IPv4 | `13.124.107.197` (EIP 아님) | PENDING; 종료 뒤 해제 확인. 이 주소를 할당 EIP처럼 삭제하지 않는다 |
| 서브넷 명시 route association | `rtbassoc-04e52ed126ae95029` | PENDING; 연결 해제 결과 |
| 별도 route table / default route | `rtb-0b3393b9c2325fdf6`, `0.0.0.0/0 → IGW` | PENDING; 의존 관계 확인 후 정리 |
| IGW | `igw-0d883adc5de5d57a9` | PENDING; 분리·삭제 결과 |
| 서브넷 | `subnet-0e41cb6e4d3caab77` | PENDING; 삭제 결과 |
| SG | `sg-030553cbc06d587a7` | PENDING; 사용 ENI가 없어진 뒤 삭제 결과 |
| SSH cloud key | `key-00e758429d0610364`, `b6-1-ssh-key` | PENDING; 삭제 결과 |
| 로컬 개인키 | `.secrets/b6-1-ssh-key.pem` | PENDING; 별도 승인 후 정리. 현재 ignored·0600을 유지 |
| VPC 및 AWS 기본 구성 | `vpc-010aff9ac6af6adce` | PENDING; 실제 종속 자원·기본 구성 처리 결과 |

이전 키 `key-05300d9117474bf5e`만 B6-1-011 복구 승인으로 삭제됐고 현재 키와는 다르다. [복구 증빙](evidence/04-security-keypair.txt).

추가 볼륨·스냅샷·EIP·NAT·ALB·DB·도메인을 이 작업에서 만들지 않았다. 미조회 계정 전체의 부재를 주장하지 않는다. 사용자가 별도로 만든 자원이 있으면 소유 범위를 확인해 목록에 추가한다. 기존 예산/연락처/IAM·프로필은 이 배포의 자동 삭제 대상이 아니다. 삭제 후에만 완료 체크·UTC·조회 증빙을 채운다.
