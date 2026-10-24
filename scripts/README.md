# CLI 생성 → 확인 → 삭제

추가 패키지 없이 Python 3 표준 라이브러리와 기존 AWS CLI·SSH·Git을 사용한다. **현재 실습 자원은 삭제됐다.** `create --apply`는 새 유료 실습을 시작하는 사용자 명령이다. 이번 작업에서는 실행하지 않았으며, 정상 전체 경로는 mock으로 검증했다. 이전 실제 CLI 배포/삭제 증빙과 자동화의 실검증 범위를 구분한다.

## 1. 본인 계정·IAM 사용자 확인과 로그인

계정 번호는 로컬 입력으로만 전달하고 채팅/파일에 붙이지 않는다. `B6_IAM_USER`는 사용할 정확한 IAM 사용자 이름으로 바꾼다. 루트/assumed role/다른 계정·서울 외 리전은 거부한다.

```sh
read -r B6_EXPECTED_ACCOUNT
export B6_EXPECTED_ACCOUNT
export B6_IAM_USER='본인-IAM-사용자이름'
aws login --profile b6-1-iam --region ap-northeast-2
```

브라우저 인증·MFA·동의는 사용자가 시크릿 창에서 직접 처리한다. 새 인증 링크/코드를 로컬에서만 사용하고 채팅·증빙에 남기지 않는다. IAM browser login에는 별도의 `SignInLocalDevelopmentAccess` 권한이 필요할 수 있다. 스크립트는 권한·프로필·캐시를 변경하거나 로그인 재시도를 하지 않는다.

## 2. 새 실습 계획과 명시적 실행

서로 다른 run/state를 사용한다. run은 영문 소문자·숫자·하이픈 3~31자다. 기존 state 또는 키 파일은 덮어쓰지 않는다.

```sh
RUN=run-20261025-a
STATE=runtime/run-20261025-a.json
./scripts/create.sh --run-id "$RUN" --state "$STATE"       # PLAN, AWS 호출 0
./scripts/create.sh --run-id "$RUN" --state "$STATE" --apply
./scripts/status.sh --state "$STATE"
./scripts/verify.sh --state "$STATE"
```

공통 옵션은 `--profile`(기본 b6-1-iam), `--region`(서울만), `--state`, `--expected-account`, `--iam-user`다. 계정·사용자는 위 환경변수로 공급하면 명령 인자에 반복할 필요가 없다. 선택적 `--ami`는 Amazon AL2023 ARM64/HVM/EBS/available/root 최소 8GiB 이하 검사를 통과해야 한다.

생성 구성은 VPC `10.0.0.0/16`, 서브넷 `10.0.1.0/24`, IGW, 별도 RT/default route/명시 연결, HTTP80 전체 IPv4+SSH22 현재 IPv4 `/32` SG, run별 ed25519 키, **t4g.nano·encrypted 8GiB gp3·standard CPU credits·IMDSv2·자동 public IPv4** 한 대다. `Project=B6-1`과 고유 `RunId` 및 이름을 함께 검증한다. 태그만으로 전체 자원을 삭제하지 않는다. 더 큰 사양·추가 EBS·NAT/EIP/ALB/IAM role로 대체하지 않는다.

기존 결정적 UserData/고정 Compose·Nginx 소스를 그대로 사용한다. nano 첫 부팅은 설치에 약 10분 걸릴 수 있다. `status`는 endpoint를 요청하지 않고 현재 AWS 상태만 읽으며, `verify`는 ACTIVE 인스턴스에만 SSH/HTTP/health/source 일치·외부 TLS 확인을 수행한다. known_hosts는 run별 `runtime/`에 격리하고 변경된 host key를 우회하지 않는다.

## 3. 정확한 state의 자원만 삭제

```sh
./scripts/destroy.sh --state "$STATE"               # PLAN
./scripts/destroy.sh --state "$STATE" --apply       # 정확 state의 삭제
./scripts/status.sh --state "$STATE"                # 삭제 후 typed 대상 읽기만
```

먼저 전체 소유·태그·연결·외부 의존성과 RT Main 여부를 검사한다. 각 지원 DryRun을 통과한 뒤 1회 실행한다. 인스턴스 종료→root EBS/자동 ENI/public 연결 제거→custom RT/서브넷/SG/IGW/키→VPC 순서다. 기본 SG/main RT/ACL은 VPC 삭제에 따르며 별도 삭제하지 않는다. detached root volume fallback도 1회 요청 후 읽기로만 대기한다. leftover ENI·외부 자원·권한/통신 오류는 중단한다. AccessDenied/timeout은 부재가 아니다.

로컬 개인키·증빙·Git은 삭제하지 않는다. 이미 DESTROYED이면 정확 대상들의 terminated/typedNotFound만 확인해 NOOP이며, 옛 IP/HTTP를 요청하지 않는다. 그 상태에서 다시 create할 수 없고 새 run/state가 필요하다.

이번 실제 정리의 폐쇄 상태는 **`runtime/cleanup-013-state.json`** 이다. 아래는 새 실습 생성이 아닌 실제 검증된 무변경 재확인이다. `historical_closed`라서 이 state의 자원 재생성/삭제 쓰기를 허용하지 않는다.

```sh
./scripts/destroy.sh --state runtime/cleanup-013-state.json --apply
```

## 중단과 비밀 보관

state는 ignored `runtime/`의 0600 atomic 파일이며 계정은 salt+fingerprint로 바인딩한다. `..`·symlink·잘못된 타입 ID/계정/리전/사용자는 거부한다. 각 생성 응답의 ID와 pending 해제를 함께 durable 저장한다. 응답 유실·모호한 결과는 UNKNOWN/pending을 유지하며 **재생성하지 않는다**. `status`로 확인하고 수동 범위 결정이 필요하다. 임의 state 편집이나 force 옵션으로 넘기지 않는다.

키는 `.secrets/key-<run>.pem`의 exclusive 0600 파일/dir0700에만 저장한다. KeyMaterial write·fsync 후 optional metadata를 처리하고 메모리 공개키 대응을 검사한다. 오류 시 프로세스를 살려 payload를 메모리에 보존하며 같은 fd로만 처리한다. 강제 종료/호스트 손실 시 개인키 복구를 보장할 수 없다. 공개/개인키 내용·digest·원시 계정/ARN/소스 IP는 로그에 넣지 않는다. ingress의 소스 IP는 메모리 stdin JSON으로만 CLI에 전달하고 argv/파일에 넣지 않는다. 프록시 환경·IP 변경은 중단하며 VPN/경로가 불명확하면 먼저 사용자 환경을 확인한다.

기존 요금은 **과거 서울 기준 약 $0.01120/h**(compute+8GiB gp3+IPv4), 전송·세금 등 제외다. 현재 요금/Free·credit 적용은 별도 확인하며 예산 상한을 보장하지 않는다. 이 자동화의 새 paid create는 offline 테스트만 했고 실제 승인된 자원 삭제와 destroyed NOOP만 live 검증했다.

## 오프라인 검증

```sh
python3 -m unittest discover -s tests -v
```

FakeAWS 정상 전체 순서, wrong identity/state/region/tag/Main/foreign 차단, 모호한 키/인스턴스 중복 생성 차단, durable refs/pending, stdin IP, private no-overwrite/optional 응답, typedNotFound 구별, traversal/symlink, volume 1회 fallback, destroyed NOOP를 검증한다. 실 AWS 생성/네트워크 테스트가 아니다.
