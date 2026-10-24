# B6-1 IAM 정책과 VPC 실습

## 현재 진행

전용 CLI 프로필 `b6-1-iam`에서 요청한 IAM 사용자·계정 일치를 확인하고 서울 VPC **`vpc-010aff9ac6af6adce`**를 생성했다. CIDR `10.0.0.0/16`, `Project=B6-1`, `Name=b6-1-vpc`, 상태 `available`을 조회로 확인했다. [인증·VPC 실행 증빙](docs/evidence/02-cli-auth-vpc.txt).

퍼블릭 서브넷 `subnet-0e41cb6e4d3caab77` (`10.0.1.0/24`, `ap-northeast-2a`)과 IGW `igw-0d883adc5de5d57a9`, 별도 route table `rtb-0b3393b9c2325fdf6`을 생성했다. IGW 연결, active 기본 경로 `0.0.0.0/0`, 서브넷 명시 연결을 조회로 검증했다. [실행 증빙](docs/evidence/03-public-network.txt) · [명령/최소 응답 JSON](docs/evidence/03-public-network.json).

기존 main route table/SG/NACL은 수정하지 않았다. public IPv4 자동할당은 꺼진 채 유지했으며, public subnet의 IGW 경로와는 별개다. 이 단계에 사용자가 추가로 조작할 사항은 없다. 다음 승인 단계는 EC2(실행 시 public IP 명시), 실제 SSH 연결과 외부 HTTP/EC2 outbound curl 검증이다. 아직 EC2는 생성하지 않았다. 브라우저 인증은 앞 단계에서 사용자가 Incognito로 직접 처리했다.

## 보안그룹·SSH 키

보안그룹 `sg-030553cbc06d587a7` (`b6-1-web-sg`)을 생성하고 HTTP 80 전체 IPv4, SSH 22 현재 공인 IPv4 `/32`만 허용하는 정확한 규칙과 기본 아웃바운드를 검증했다. SSH 키 `b6-1-ssh-key`는 현재 `key-00e758429d0610364` (ed25519)이며 로컬 `.secrets/b6-1-ssh-key.pem`에 비공개 저장했다. 파일 0600·디렉터리 0700·Git ignored·공개키 대응 검증을 통과했다. [실행·트러블슈팅 증빙](docs/evidence/04-security-keypair.txt) · [명령/최소 결과 JSON](docs/evidence/04-security-keypair.json).

최초 키는 Worker 응답 처리 오류로 개인키를 저장하지 못했다. 코드 수정·fixture·독립 검토와 사용자 명시 승인 후 이전 키 `key-05300d9117474bf5e`와 자기 빈 파일만 삭제하고 동일 이름으로 재생성해 복구했다. 위 SG/현재 키 ID는 후속 정리 추적용이다.

이 단계에 추가 수동 조작은 없다. **개인키는 공유하거나 커밋하지 않는다.** 공인 IP가 바뀌면 SSH `/32` 변경 승인을 요청한다. EC2 생성·실제 SSH·HTTP 검증은 아직 실행하지 않았으며 다음 승인 단계다.

## 정책 사용

[b6-1-all-in-one.json](policies/b6-1-all-in-one.json) 하나에 EC2 실습·예산 관리·이메일 연락처 확인 권한을 합쳤다. 계정/자원 ID를 치환할 필요 없이 JSON 전체를 사용한다.

1. IAM → 정책 → 정책 생성 → **JSON** 탭에서 파일 내용을 붙여넣는다.
2. 내용을 검토하고 정책 이름을 **B6-1-AllInOne**으로 저장한다.
3. 사용할 IAM 사용자를 확인하고 사용자가 직접 이 정책을 연결한다. 이 저장소에서 연결·권한 부여는 실행하지 않았다.

- EC2 조회·생성·수정·정리는 **서울(ap-northeast-2)** 요청만 허용한다.
- Budget과 이메일 연락처 작업에는 리전 조건이 없다. 예산/알림/구독 생성·변경·삭제는 `budgets:ModifyBudget`, 조회는 `budgets:ViewBudget`으로 처리한다.
- 모든 Statement는 `Resource:*`다. 계정/자원 ID, 태그, 인스턴스 타입, 수량·지출 상한 조건을 두지 않은 넓은 권한 구성이다. Budget은 강제 지출 상한이 아니다.
- Budget Actions, SNS, 태그가 있는 예산/연락처 생성, Billing 콘솔의 부가 권한, IAM 접근 키 관리 권한은 포함하지 않았다. 이메일 확인 코드는 사용자가 직접 처리한다.
- 아래 전체 정책의 모든 권한을 실제 검증한 것은 아니다. 현재 진행에서 확인한 IAM 인증·VPC·퍼블릭 네트워크·보안그룹 및 SSH 키 대응 단계만 실제 검증했다. IAM Allow는 SCP의 명시적 Deny나 닫힌 계정을 해결하지 못하며, 기존 다른 정책과의 최종 유효권한도 별도다.

공식 권한 표: [EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html), [Budgets](https://docs.aws.amazon.com/service-authorization/latest/reference/list_budgets.html), [이메일 연락처](https://docs.aws.amazon.com/service-authorization/latest/reference/list_notificationscontacts.html).
