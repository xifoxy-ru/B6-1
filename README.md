# B6-1 IAM 정책과 VPC 실습

## 현재 진행

전용 CLI 프로필 `b6-1-iam`에서 요청한 IAM 사용자·계정 일치를 확인하고 서울 VPC **`vpc-010aff9ac6af6adce`**를 생성했다. CIDR `10.0.0.0/16`, `Project=B6-1`, `Name=b6-1-vpc`, 상태 `available`을 조회로 확인했다. [인증·VPC 실행 증빙](docs/evidence/02-cli-auth-vpc.txt).

CreateVpc에 따르는 AWS 기본 ACL/SG/main route table·DHCP 옵션 연결 외에 별도 구성요소를 생성하지 않았다. Public Subnet/IGW/라우팅/EC2와 외부 웹 검증은 다음 승인 단계다. 브라우저 인증은 사용자가 Incognito에서 직접 처리했다.

## 정책 사용

[b6-1-all-in-one.json](policies/b6-1-all-in-one.json) 하나에 EC2 실습·예산 관리·이메일 연락처 확인 권한을 합쳤다. 계정/자원 ID를 치환할 필요 없이 JSON 전체를 사용한다.

1. IAM → 정책 → 정책 생성 → **JSON** 탭에서 파일 내용을 붙여넣는다.
2. 내용을 검토하고 정책 이름을 **B6-1-AllInOne**으로 저장한다.
3. 사용할 IAM 사용자를 확인하고 사용자가 직접 이 정책을 연결한다. 이 저장소에서 연결·권한 부여는 실행하지 않았다.

- EC2 조회·생성·수정·정리는 **서울(ap-northeast-2)** 요청만 허용한다.
- Budget과 이메일 연락처 작업에는 리전 조건이 없다. 예산/알림/구독 생성·변경·삭제는 `budgets:ModifyBudget`, 조회는 `budgets:ViewBudget`으로 처리한다.
- 모든 Statement는 `Resource:*`다. 계정/자원 ID, 태그, 인스턴스 타입, 수량·지출 상한 조건을 두지 않은 넓은 권한 구성이다. Budget은 강제 지출 상한이 아니다.
- Budget Actions, SNS, 태그가 있는 예산/연락처 생성, Billing 콘솔의 부가 권한, IAM 접근 키 관리 권한은 포함하지 않았다. 이메일 확인 코드는 사용자가 직접 처리한다.
- 아래 전체 정책의 모든 권한을 실제 검증한 것은 아니다. 현재 진행에서 확인한 IAM 인증·VPC 생성 단계만 실제 검증했다. IAM Allow는 SCP의 명시적 Deny나 닫힌 계정을 해결하지 못하며, 기존 다른 정책과의 최종 유효권한도 별도다.

공식 권한 표: [EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html), [Budgets](https://docs.aws.amazon.com/service-authorization/latest/reference/list_budgets.html), [이메일 연락처](https://docs.aws.amazon.com/service-authorization/latest/reference/list_notificationscontacts.html).
