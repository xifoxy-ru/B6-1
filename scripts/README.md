# 실행·운영 안내

현재 `capture-016-20261026`의 클라우드 자원은 **삭제 완료**입니다. [사진·원본 기록](../docs/evidence-guide.md), [삭제 확인](../docs/cleanup-checklist.md), [문제 해결](../docs/troubleshooting.md)을 먼저 보세요. 이 문서는 사용법이며 지금 새 자원을 만들라는 지시가 아닙니다.

## 명령 역할

| 명령 | 하는 일 |
|---|---|
| `create.sh` | 기본은 계획만 준비. `--apply`를 붙이면 실제 생성·비용 발생 |
| `status.sh` | 정해진 자원의 상태 조회. 완료된 실습은 정확한 부재/종료만 확인 |
| `verify.sh` | 실행 중인 새 서버의 SSH·Docker·내부/외부 HTTP 확인 |
| `destroy.sh` | 기본은 계획만 표시. `--apply`는 정확한 대상 정리 |

기존 Bash 3.2·AWS CLI·curl·ssh·ssh-keygen·git·base64·sed·awk·dd·shasum·jq를 사용합니다. jq는 JSON 데이터 처리용입니다. 새 설치는 하지 않았고 Python 실행 도구는 Git 이력에 남겼습니다.

<a id="capture"></a>
## 단계별 촬영 옵션

- `create`·`destroy`의 `--capture`는 사용자 Terminal에서만 씁니다. 입력·출력이 TTY가 아니면 변경 전에 거부합니다. `| tee`나 파일 입출력으로 우회하지 않습니다.
- 실제 명령·결과 뒤 한글 제목과 PNG 이름이 나옵니다. 사진을 저장하고 확인받은 뒤 **빈 Enter 한 번**을 누릅니다. 자동 진행·시간 제한·화면 자동 지우기는 없습니다.
- 생성은 VPC → subnet → IGW/라우팅 → SG/키 → EC2, 삭제는 EC2/EBS/ENI → RT → subnet/SG → IGW/cloud key → VPC의 다섯 그룹입니다.
- 긴 출력은 같은 정지 지점에서 part1/2로 나눠 촬영합니다. HTML이나 다시 그린 콘솔 화면으로 대체하지 않습니다.
- EOF·Ctrl-C로 중단하면 state의 촬영 대기 표식이 남아 다음 변경을 막습니다. 부분 자원·비용을 확인하기 전 **재실행하거나 표식을 직접 지우지 않습니다.**

<a id="commands"></a>
<details>
<summary>▶ 인증 준비와 명령 예시</summary>

프로필은 `b6-1-iam`, 리전은 서울입니다. 로그인 URL·코드·비밀번호·MFA 값은 사용자 로컬 Terminal과 시크릿 창에서만 처리합니다. 채팅에 보내지 않습니다.

```sh
aws login --profile b6-1-iam --region ap-northeast-2 --remote
bash
set +x
IFS= read -r -s B6_EXPECTED_ACCOUNT; export B6_EXPECTED_ACCOUNT; printf '\n'
IFS= read -r B6_IAM_USER; export B6_IAM_USER
clear
# 이미 삭제된 016의 읽기 전용 확인. 옛 endpoint에는 요청하지 않음.
./scripts/status.sh --state runtime/capture-016-state.json
```

별도 새 실습은 **새 이름·새 state·새 키**로 시작합니다. 계획·권한·비용을 검토한 다음 실제 생성하고, 필요한 live 사진을 확보한 뒤 삭제 대상을 확인합니다.

```sh
unset B6_RUN_PLAN
RUN_ID=lab-$(date -u +%Y%m%d%H%M%S)
STATE=runtime/$RUN_ID-state.json
./scripts/create.sh --run-id "$RUN_ID" --state "$STATE"  # 계획만
# 계획 확인 뒤에만 실행하는 형식
./scripts/create.sh --run-id "$RUN_ID" --state "$STATE" --apply --capture
./scripts/status.sh --state "$STATE" --section network
./scripts/status.sh --state "$STATE" --section security
./scripts/status.sh --state "$STATE" --section compute
./scripts/verify.sh --state "$STATE"
# 필수 사진·정확한 삭제 대상 확인 뒤에만
./scripts/destroy.sh --state "$STATE" --apply --capture
```

016 당시에는 별도 검토한 외부 `B6_RUN_PLAN`을 읽었습니다. 위 예시는 새 실습의 기본 runtime 계획을 사용하며 완료된 016을 재실행하지 않습니다.

</details>

<a id="configuration"></a>
<details>
<summary>▶ 실제 실행 구성과 안전장치</summary>

- 구성: 서울 t4g.nano ARM64/512MiB, 암호화 8GiB gp3, standard CPU credits, IMDSv2/hop1, 자동 공인 IPv4. 추가 EBS·NAT·EIP·ALB·DB·도메인·HTTPS·instance IAM role·큰 사양 fallback은 쓰지 않았습니다.
- 고정 이미지: `nginx:1.30.6-alpine@sha256:4f7cab9e1cd018f80e67f31e02dc0c6d18560b19504461c4f3dd37e5c63a74c5`. Docker 25.0.18·Compose v2.39.4, IPv4 host `0.0.0.0:80 → container 80`.
- [Compose](../deploy/compose.yaml) · [Nginx 설정](../deploy/nginx.conf) · [UserData](../deploy/user-data.sh.tpl) · [Shell renderer](../deploy/render-user-data.sh)는 그대로입니다. 당시 서버에서 `cd /opt/b6-1 && sudo docker compose up -d`를 실행했습니다. 지금 삭제된 서버에서 실행할 수 있는 명령이 아닙니다.
- state는 실행 코드가 아닌 ignored JSON(0600), runtime·키 폴더는 0700입니다. 경로 이탈·symlink·기존 키 덮어쓰기를 거부합니다.
- 지정 IAM 신원·리전·소유자·태그·연결·Main/다른 자원을 검사하고, 지원되는 DryRun 뒤 한 번씩 변경합니다. 모호한 결과는 UNKNOWN으로 멈추며 무작정 재생성하지 않습니다.
- 내 IP는 HTTPS/no-proxy로 읽어 메모리·JSON stdin에서만 사용합니다. 계정·ARN·원시 IP·키 내용은 출력하지 않습니다. 개인키는 exclusive 파일에 먼저 저장·동기화한 뒤 메타데이터를 처리하며 old/new 키를 정리 후에도 로컬에 보존합니다.
- [기존 오프라인 검사 출력](../docs/evidence/08-guided-capture/08-offline-tests.txt)은 가짜 AWS만 사용했습니다. nonTTY 거부·일반 동작·UNKNOWN·키 저장·Enter/EOF/Ctrl-C 검증 범위는 실제 배포 증거와 구분합니다.

</details>

<a id="basics"></a>
## 구조·과금·정리의 이유

| 용어 | 쉬운 뜻 |
|---|---|
| VPC / Subnet | 내 네트워크 울타리 / 안의 작은 구역 |
| Route Table / IGW | 통신이 갈 길을 적은 지도 / 인터넷 문 |
| EC2 / EBS | 빌린 컴퓨터 / 저장 장치 |
| SG / IAM | 들어올 통신 허용 / AWS에서 할 작업 허용 |
| Docker / Nginx | 실행 상자 / 웹 페이지를 보내는 프로그램 |

브라우저 → 공인 IP·IGW → public subnet → SG80 → EC2 host80 → Docker80 → Nginx로 요청이 갑니다. 돌아갈 길은 IGW 경로가 맡습니다. subnet 자동 IP 할당은 껐지만 EC2 생성 때 공인 IP를 붙였습니다.

컴퓨터 사용 시간·EBS·공인 IPv4·전송량이 비용 요인입니다. 예산 알림은 강제 지출 상한이 아닙니다. EC2를 먼저 종료하고 디스크·ENI·IP 연결 제거를 확인한 뒤 네트워크 의존성을 풀어야 남은 비용·삭제 오류를 줄일 수 있습니다. [최소 권한·무료 적용·청구의 한계](../README.md#limits)는 완료 상태와 별개입니다.
