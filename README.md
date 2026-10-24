# B6-1 · 실습 정리 완료 / CLI lifecycle

현재 상태: **CLEANED**. EC2는 terminated, root EBS·자동 ENI·지정한 네트워크/클라우드 키/VPC는 정확한 typedNotFound로 확인했다. 자동 public IPv4 연결도 제거됐다. 이전 주소 `http://13.124.107.197/`는 **과거 증빙용이며 다시 요청하지 않는다**. 재할당될 수 있어 현재 서비스 주소가 아니다.

[실제 삭제 증빙](docs/evidence/06-cleanup.txt) · [명령/결과 JSON](docs/evidence/06-cleanup.json) · [자원별 최종 체크리스트](docs/cleanup-checklist.md) · [스크립트 테스트](docs/evidence/06-scripts-tests.txt)

## CLI 사용

전체 설명과 로컬 계정·IAM 사용자 입력/시크릿 로그인 방법은 [scripts/README.md](scripts/README.md)에 있다. Python3 표준 라이브러리·기존 AWS CLI/SSH/Git만 사용하며, 기본 동작은 PLAN이다.

```sh
./scripts/create.sh --run-id run-example --state runtime/new-run.json
# 본인 계정/IAM 사용자 환경을 설정하고 새 유료 실습을 원할 때만:
./scripts/create.sh --run-id run-example --state runtime/new-run.json --apply
./scripts/status.sh --state runtime/new-run.json
./scripts/verify.sh --state runtime/new-run.json
./scripts/destroy.sh --state runtime/new-run.json       # PLAN
./scripts/destroy.sh --state runtime/new-run.json --apply
```

새 생성은 고유 run/state/키를 사용하고 Seoul t4g.nano ARM64·encrypted8GiB gp3·standard CPU credit·IMDSv2·자동 IPv4 한 대와 전용 네트워크를 만든다. 기존 app/UserData/Compose/Nginx 원본은 그대로 사용한다. **새 자동 create는 mock offline 전체 경로만 검증했고 실제 유료 재생성은 하지 않았다.** 실제 정리는 독립 사전 검토된 exact executor로 수행했다. 제품 destroy의 이미 삭제된 상태 NOOP도 live 확인했다.

현재 정리 기록 `runtime/cleanup-013-state.json`은 폐쇄된 과거 상태이며 새 생성 상태와 분리된다. 아래 명령은 정확 대상만 읽는 무변경 재확인이다. 환경변수 설정이 먼저 필요하다.

```sh
./scripts/destroy.sh --state runtime/cleanup-013-state.json --apply
python3 -m unittest discover -s tests -v
```

소유·계정·IAM 사용자·서울 리전·RunId/태그·연결·foreign dependency를 확인하고, 각 지원 DryRun 뒤 한 번만 변경한다. UNKNOWN 응답은 중단/보존하며 create를 반복하지 않는다. raw 소스 IP는 memory stdin으로만 전달한다. 키는 run별 exclusive0600·dir0700 파일에 durable 저장 후 optional metadata를 처리한다. 현재 개인키 `.secrets/b6-1-ssh-key.pem`은 **삭제하지 않고 비공개·Git ignored로 보존**했다. IAM/예산/연락처/프로필도 보존했다.

## 보존한 과거 배포 증빙

다음은 삭제 전 실제 실행 결과이며 현재 실행 중이라는 뜻이 아니다. HTTP200/소스 일치·SSH·Docker healthy·EC2 외부 TLS200을 확인했던 기록과 원본 이미지/구성도를 바이트 그대로 보존했다.

- [배포 명령/실제 결과](docs/evidence/05-ec2-deploy.txt) · [JSON](docs/evidence/05-ec2-deploy.json)
- [실제 외부 브라우저 원본 화면](docs/evidence/05-external-http.png) · [실제 캡처 Docker ps stdout 화면](docs/evidence/05-docker-ps.png)
- [아키텍처 PNG](docs/architecture.png) · [SVG](docs/architecture.svg) · [실제 트러블슈팅](docs/troubleshooting.md)
- [app](app/index.html) · [Compose](deploy/compose.yaml) · [UserData](deploy/user-data.sh.tpl) · [IAM 정책](policies/b6-1-all-in-one.json)

과거 서울 요금 추정은 compute+8GiB gp3+IPv4 약 **$0.01120/h**, 전송·세금 등 제외였다. 이번 정확 대상은 정리됐지만 계정 전체 청구가 0이라고 주장하지 않는다. 향후 요금/Free·credit 적용은 별도 확인하며 Budget은 강제 지출 상한이 아니다.
