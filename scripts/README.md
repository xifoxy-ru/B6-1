# AWS CLI Shell lifecycle

실행 경로는 Bash 3.2와 실제 `aws` CLI 명령이다. Python/Boto3 엔진·renderer는 제거했고 Git 이력에 남겼다. 기존 `aws`, `curl`, `ssh`, `ssh-keygen`, `git`, `base64`, `sed`, `awk`, `dd`, `shasum`, `/usr/bin/jq`를 사용한다. jq는 API JSON/데이터 state 처리용이며 새 설치는 하지 않는다.

계정은 로컬 메모리 환경변수 `B6_EXPECTED_ACCOUNT`, 정확한 IAM 사용자 이름은 `B6_IAM_USER`로 공급한다. 계정/ARN/원시 소스 IP/키는 증빙에 출력하지 않는다. 공식 `aws login --profile b6-1-iam --region ap-northeast-2 --remote`의 URL/코드는 사용자 로컬 시크릿 창·Terminal에서만 처리한다.

```sh
bash  # 아래 read 옵션은 Bash 기준. 로그인 URL/코드는 채팅에 보내지 않는다.
set +x
IFS= read -r -s B6_EXPECTED_ACCOUNT; export B6_EXPECTED_ACCOUNT; printf '\n'
IFS= read -r B6_IAM_USER; export B6_IAM_USER
clear
# 완료된 이번 state: 읽기 전용 typedNotFound/terminated 확인, endpoint 요청 없음
./scripts/status.sh --state runtime/shell-015-state.json
# 별도 새 실습은 새 run/state로 PLAN부터. 실제 생성은 비용·입력을 검토한 뒤에만.
RUN_ID=lab-$(date -u +%Y%m%d%H%M%S)
STATE=runtime/$RUN_ID-state.json
./scripts/create.sh --run-id "$RUN_ID" --state "$STATE"
./scripts/create.sh --run-id "$RUN_ID" --state "$STATE" --apply
./scripts/status.sh --state "$STATE" --section network
./scripts/status.sh --state "$STATE" --section security
./scripts/status.sh --state "$STATE" --section compute
./scripts/verify.sh --state "$STATE"
# 필요한 실제 증빙 확보 및 정확한 삭제 대상 검토 뒤에만
./scripts/destroy.sh --state "$STATE" --apply
```

기본 create/destroy는 PLAN이고 `--apply`가 필요하다. 새 run/state/키는 고유하며 기존 파일·모호한 UNKNOWN 결과를 재생성하지 않는다. state는 source/eval 없이 jq로 읽는 ignored 0600 JSON, runtime/dir는 0700이며 traversal/symlink를 거부한다. 계정은 salt+fingerprint 바인딩이다. 각 지원 DryRun 뒤 한 번만 변경하고 ID와 pending 해제를 함께 atomic 저장한다. 소스 IP는 검증된 HTTPS/no-proxy 메모리 조회 후 stdin JSON으로만 ingress에 전달한다.

현재 계획은 t4g.nano ARM64/512MiB, encrypted8GiB gp3, standard credit, IMDSv2/hop1, 자동 public IPv4 한 대다. 추가 EBS/NAT/EIP/ALB/DB/도메인/HTTPS/IAM role이나 큰 사양 fallback은 없다. 기존 고정 Compose/Nginx와 UserData 소스는 그대로이며 새 Shell renderer가 동일 바이트를 만든다. 비용/credit 적용은 UNKNOWN이고 강제 상한이 아니다.

KeyMaterial은 AWS CLI query에서 exclusive private FD로만 전달하고 `dd conv=fsync`/sync로 저장을 먼저 완료한 뒤 optional metadata를 읽는다. 개인키 내용·공개키·digest를 로그에 넣지 않는다. old/new 키는 로컬에 남고 cleanup에서도 삭제하지 않는다. 쓰기/응답 실패 시 UNKNOWN으로 멈추고 수동 조정하며 blind retry/import/regeneration은 없다.

삭제는 전체 owner/RunId/태그/링크/RT Main/foreign guard를 먼저 확인하고 exact instance→root/ENI/public 연결→custom network/key→VPC 순서다. default 자원을 따로 지우지 않으며 leftover ENI는 중단한다. 이미 삭제된 state는 typedNotFound/terminated만 확인하고 옛 endpoint를 요청하지 않는다. 새 생성에는 새 run/state가 필요하다.

실제 Terminal 자동조작은 CUA 안전정책으로 불가하다. [캡처 체크리스트](../docs/capture-checklist.md)의 사용자 실제 실행·원본 PNG가 필요하며 HTML 렌더 대체는 하지 않는다. 필수 화면 PENDING이면 cleanup을 보류하고 비용/대상 상태를 PM에게 알린다.

```sh
bash tests/test-shell.sh   # FakeAWS·임시 fixture만, 실제 AWS/network 0
```

테스트는 정상 호출 순서·DryRun, Main/태그/foreign/신원/리전 차단, UNKNOWN key/instance 중복 방지, no-overwrite, stdin IP/키 비노출, typedNotFound와 권한 오류 구별, 결정적 renderer를 확인한다. 이전 015의 `shell-015-20261025`는 실제 runtime 확인·native PNG 6종 확보 후 CLEANED다. 첫 create는 빈 SG 뒤 CLI stdin 입력 검증에서 중단했고, `--ip-permissions file:///dev/stdin`으로 수정·독립 검토한 외부 전용 resume가 기존 network를 재사용해 남은 단계만 실행했다. 중단 없는 full run이었다는 주장은 하지 않는다. 015 당시 정상 전체 create→destroy 순서는 FakeAWS로 검증했다. 이후 별도 승인된 016에서는 아래처럼 사용자 foreground 촬영 실행·정리를 마쳤다.

## 선택형 단계별 촬영 `--capture`

[08 촬영 체크리스트](../docs/capture-checklist-08.md)에 실제 사용자 단계별 촬영과 최종 CLEANED 결과를 남겼습니다. 사용자 native Terminal에서만 실행합니다. 원래 옵션 없는 동작은 그대로입니다.

- create는 VPC → subnet → IGW/라우팅 → SG/키 → EC2의 다섯 지점에서 멈춥니다.
- destroy는 EC2/EBS/ENI → RT → subnet/SG → IGW/cloud key → VPC 완료 뒤 멈춥니다.
- 한글 제목과 파일명대로 저장한 후 PM 확인을 받고 빈 Enter 한 번을 누릅니다. 자동 진행·타임아웃·자동 화면 지우기는 없습니다.
- `--capture`의 stdin/stdout이 TTY가 아니면 API 호출·state/키 생성 전 거부합니다. `| tee`나 입력/출력 파일로 우회하지 마세요.
- EOF/중단 시 state의 `capture_waiting` 표식이 남아 다음 변경 실행을 막습니다. 부분 자원/비용을 PM과 검토하기 전 같은 명령을 재실행하지 않습니다. 표식을 직접 지우거나 state를 편집하지 마세요.

아래는 **이번 016에서 이미 사용한 실행 기록**입니다. 현재 자원은 삭제됐으므로 같은 create/destroy를 재실행하지 않습니다. 새 실습은 새 run/state와 계획이 필요합니다. `B6_RUN_PLAN`은 검토된 외부 계획 경로를 PM이 알려 줍니다. 로그인/계정 환경변수 준비는 위와 같습니다.

```sh
export B6_RUN_PLAN=/Users/sgang/bin/harness-workspaces/B6-1/capture-016/run-plan.json
./scripts/create.sh --run-id capture-016-20261026 --state runtime/capture-016-state.json --apply --capture
# 필수 live 사진과 exact 삭제계획 검토 완료 후 별도 시작
./scripts/destroy.sh --state runtime/capture-016-state.json --apply --capture
```

오프라인 검사는 실제 자원 없이 가짜 AWS를 사용합니다. 일반 동작 회귀와 nonTTY 거부는 `bash tests/test-shell.sh`, 실제 test TTY에서 Enter/EOF/Ctrl-C를 확인하는 fixture는 `--capture-success-fixture`, `--capture-eof-fixture`, `--capture-interrupt-fixture`입니다. 이 fixture의 임시 키는 가짜 문자열이며 실키를 읽지 않습니다.

현재 `runtime/capture-016-state.json`은 DESTROYED입니다. `./scripts/status.sh --state runtime/capture-016-state.json`은 typedabsence만 읽으며 endpoint에 요청하지 않습니다. 이번 19장 PNG와 중간 PENDING→READY→성공 기록은 08 폴더에 원본으로 보존했습니다.
