# B6-1 IAM 템플릿

[b6-1-all-in-one.json](policies/b6-1-all-in-one.json) 하나를 사용한다. **계정 하나**에서 서울 EC2 실습·`B6-1-` 예산 관리·이메일 연락처 확인 권한을 함께 담았다. 기존 세 정책의 Statement를 변경 없이 합쳤으며, 결합된 권한을 같은 담당 역할에 부여하는 구성이다.

값을 치환하고 Resource/Condition을 검토한 뒤 IAM 정책 편집기의 **JSON** 탭에 직접 붙여넣는다.

## 값 치환과 적용 순서

1. 대상 계정 하나와 담당 역할을 확인하고 아래 `{{...}}`를 실제 승인된 값으로 모두 치환한다. 모든 `{{ACCOUNT_ID}}`에는 **동일한 숫자 12자리 계정 ID**를 넣는다. 치환본은 Git에서 제외한 `rendered/` 또는 `output/`에 저장한다. 원본 템플릿은 보존한다.
2. JSON 문법·미치환 placeholder·ARN의 계정/서울 리전·Resource/Condition을 검토한 뒤 **이 통합 정책 하나를** 해당 역할에 붙여넣는다. 이 저장소에서 연결/권한 부여는 실행하지 않았다.
3. 새 네트워크라면 **두 단계**다. 먼저 생성 부분을 검토해 `Project=B6-1` 태그를 붙여 VPC/서브넷/SG/키 등을 준비한다. 아직 없는 launch 입력 ID를 임의 값으로 만들지 말고, `LaunchApprovedInputs` 문장은 첫 적용에서 제외한다. 실제 ID가 생기면 그 문장을 다시 넣고 해당 ID로 치환·재검토해야 RunInstances를 사용할 수 있다. 기존 자원을 쓴다면 처음부터 승인된 실제 ID를 사용한다.

| placeholder | 치환 전 확인 |
| --- | --- |
| `{{ACCOUNT_ID}}` | 대상 AWS 계정의 숫자 **12자리**. 이메일·별칭·임의 샘플 번호 사용 금지 |
| `{{AMI_ID}}` | 서울에서 승인한 공개 EBS 기반 Linux AMI, `ami-` + 8/17자리 소문자 hex. AMI 아키텍처와 인스턴스 타입 일치 확인 |
| `{{SUBNET_ID}}`, `{{SG_ID}}` | `subnet-` / `sg-` + 8/17자리 hex. 같은 승인 VPC의 서브넷/SG인지 확인 |
| `{{KEY_PAIR_ID}}` | `key-` + 8/17자리 hex인 **키 페어 ID**. CLI `--key-name`은 대응하는 실제 이름을 별도로 사용 |
| `{{INSTANCE_TYPE}}` | 승인한 작은 타입 하나. 치환 검사는 `(t2|t3|t3a|t4g).(nano|micro)` 형식으로 제한. 실제 서울 제공 여부·AMI 호환성·Free 적격성·가격은 별도로 확인 |

형식 검사는 실제 자원 존재/소유·요금 적격성을 검증하지 않는다. 네트워크 첫 단계 치환본에서도 남겨 둔 `{{...}}`는 없어야 한다.

## EC2 실행 전제와 예외

- CLI 경로는 `create-vpc/subnet/route-table/internet-gateway/security-group/key-pair` → attach/associate/create-route → SG 규칙 → `run-instances` → describe/wait → 정리다. 새 자원 생성 요청에 `Project=B6-1` 태그가 필요하다. `CreateTags`는 이 생성 API 안에서만 허용하며 태그 키는 Project/Name만 허용한다. 기존 임의 자원에 Project 태그를 붙이는 권한은 없다.
- RunInstances는 고정 AMI/subnet/SG/key 입력과 새 instance/volume/network-interface를 나눠 허용한다. `--tag-specifications`에 **instance, volume, network-interface 각각** Project 태그를 넣고 `--metadata-options HttpTokens=required`를 사용한다. 새 기본 ENI에 public IPv4를 명시하고 EBS 기반 on-demand 인스턴스 1대만 사용한다. launch template/기존 ENI/Spot/추가 스냅샷/고객 관리 KMS 키/instance profile은 이 템플릿의 경로가 아니다.
- 수량 1대, EBS 8~10GiB, HTTP80 공개·SSH22 내 IP 제한은 요청/SG 검토에서 지킨다. 이 IAM 템플릿이 포트/CIDR·수량·지출 상한을 강제한다고 주장하지 않는다. 인스턴스 타입 placeholder는 비용 보장이 아니다.
- Describe 작업은 자원별 권한이 없어 `Resource:*`이며 서울 조건만 적용한다. B6-1 태그로 조회 결과 전체를 숨기지 못한다. 관리/정리는 태그된 자원만 허용한다. 다른 역할이 이미 붙인 같은 태그도 신뢰 경계이므로 별도 공유 계정에서 절대 최소 정책으로 간주하지 않는다.
- SG 규칙 추가는 태그된 부모 SG로 제한한다. **규칙 자체의 TagSpecifications는 사용하지 않는다**. SAR에서 tagged rule은 별도 security-group-rule 권한 평가를 받으므로 이 템플릿에는 포함하지 않았다.
- 종료 시 root EBS/기본 ENI의 자동 삭제 설정을 확인한다. 남은 **태그된** EBS/ENI만 별도 삭제 가능하다. 기본 라우트 테이블/default SG/ACL/DHCP 등 자동 생성·미태그 자원에 임의 태그/변경 권한을 주지 않는다. 생성한 사용자 라우트/연결과 SG/키를 정리한 뒤 VPC를 삭제한다. 삭제 권한은 실제 삭제 승인과 별개다.

## Budget / 이메일 연락처

`CreateBudget`, `UpdateBudget`, `DeleteBudget`와 예산 알림/구독 변경의 IAM action은 **`budgets:ModifyBudget`**, 조회는 **`budgets:ViewBudget`**다. `budgets:CreateBudget`은 없다. 예산 이름은 `B6-1-...`, 기본 Billing View, **태그 없는 예산**을 전제로 한다. 예산 태그, Budget Actions, SNS는 포함하지 않았다. 계정 전체 예산 열거/목록이나 Billing 콘솔의 부가 조회는 이 prefix 정책으로 되지 않을 수 있다. 필요한 경우 별도 읽기 범위를 검토하며 `aws-portal:ModifyBilling` 같은 넓은 수정 권한을 대신 넣지 않는다. 예산은 지출의 강제 상한이 아니다.

연락처 Create/List는 SAR에서 자원 ARN 제한을 지원하지 않아 `Resource:*`가 필요하다. Get/SendActivationCode/Activate는 지정 계정의 emailcontact/*로 제한한다. **태그 없이 생성**하며 삭제·태그 관리·notifications 서비스 설정 권한은 제외했다. 이메일 수신/활성화 링크·코드는 사용자가 직접 처리한다.

공식 action/resource/condition 자료를 검토하고 오프라인 JSON·치환·크기 검사를 했다. 실제 AWS 권한 검증/연결/배포는 하지 않았다. 계정 상태는 미확인이고 IAM Allow는 SCP Deny나 닫힌 계정을 해결하지 못한다. 다른 기존 정책이 있으면 이 Allow 템플릿만으로 최종 권한 상한을 만들 수 없다.

## 공식 근거

- [EC2 SAR](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html), [CLI RunInstances](https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html), [태그 생성 권한](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/supported-iam-actions-tagging.html)
- [Budgets SAR/API 매핑](https://docs.aws.amazon.com/service-authorization/latest/reference/list_budgets.html), [Cost Management 정책 예시](https://docs.aws.amazon.com/cost-management/latest/userguide/billing-example-policies.html)
- [Contacts SAR](https://docs.aws.amazon.com/service-authorization/latest/reference/list_notificationscontacts.html)
