# B6-1 · AWS 웹 서버 만들기

**실습 서버를 만들고, 실제 화면을 찍고, 삭제까지 마쳤습니다.**

- 현재: **CLEANED** — 이번 실습 자원 정리 완료, 2026-10-25 11:41:32 UTC.
- 환경: 서울 AWS · Amazon Linux 2023 · EC2 1대 · Docker 안의 Nginx.
- 실행 도구: 읽을 수 있는 **AWS CLI Shell**. Python 실행 도구는 Git 이력에 보존했습니다.

## 먼저 알아둘 한계

| 항목 | 정확한 상태 |
|---|---|
| 최소 권한 | **완전히 충족하지 못함.** 정책은 서울의 다른 자원과 예산·연락처 작업도 허용합니다. 딱 이 실습에만 필요한 권한은 아닙니다. |
| 루트 계정 미사용 | 배포 CLI는 정해진 IAM 사용자로 확인했습니다. 계정 관리·MFA 설정 세션까지 포함한 **전 과정 루트 미사용은 입증하지 못했습니다.** |
| 프리 티어·크레딧 | 실제 적용 여부 **미확인**. 작은 서버를 썼다고 무료가 되지는 않습니다. |
| 비용 화면 | 10월·필터 0에서 **US$0.01** 표시. 최종 청구액이나 이번 실습만의 비용인지는 확인하지 못했습니다. |
| 구조 그림 | 같은 구성의 **이전 실습의 자원 번호**가 들어 있습니다. 이번 자원 번호는 network·compute·정리 증빙을 봅니다. |

## 필수 제출물 4개

| 제출물 | 바로 보기 |
|---|---|
| 구성과 통신 흐름 그림 | [아키텍처 PNG](docs/architecture.png) — VPC·서브넷·IGW·EC2·SG·통신 흐름 |
| 외부 접속 증명 | **방법 A: 브라우저** · [실제 화면](docs/evidence/07-shell-replay/07-external-browser.png) |
| 문제 해결 기록 | [트러블슈팅 보고서](docs/troubleshooting.md) · [이번 실습 문제·해결](docs/evidence/07-shell-replay/07-run-summary.txt) |
| 자원 정리 기록 | [삭제 체크리스트](docs/cleanup-checklist.md) · [삭제 확인 화면](docs/evidence/07-shell-replay/07-cleanup-terminal.png) |

외부 검증에 쓴 과거 주소: `http://43.203.227.198/`. **이미 해제된 주소이므로 다시 접속하지 마세요.**

## 명세와 실제 결과

| 명세가 요구한 일 | 이번 실습 결과 | 증빙 |
|---|---|---|
| 서울 리전에 구성 | `ap-northeast-2` | [EC2 화면](docs/evidence/07-shell-replay/07-compute-terminal.png) |
| VPC 1개·public subnet 1개·IGW 연결 | `10.0.0.0/16` 안의 `10.0.1.0/24` | [network 화면](docs/evidence/07-shell-replay/07-network-terminal.png) |
| 인터넷으로 나가는 길 | `0.0.0.0/0 → IGW`, 서브넷에 route table 연결 | [network 화면](docs/evidence/07-shell-replay/07-network-terminal.png) |
| EC2 1대·SSH 접속·Nginx 실행 | 실제 SSH 성공, 컨테이너 healthy | [verify 화면](docs/evidence/07-shell-replay/07-verify-terminal.png) |
| EC2 안에서 `localhost` 200 | `/`와 `/health` 모두 HTTP 200 | [verify TXT](docs/evidence/07-shell-replay/07-verify.txt) |
| 인터넷 outbound 통신 | EC2에서 `https://example.com` 200 | [verify 화면](docs/evidence/07-shell-replay/07-verify-terminal.png) |
| HTTP 80은 모두에게 허용 | `tcp80 / 0.0.0.0/0` | [security 화면](docs/evidence/07-shell-replay/07-security-terminal.png) |
| SSH 22는 내 IP만 허용 | 당시 IP `/32`와 일치. 원시 IP는 숨김 | [security 화면](docs/evidence/07-shell-replay/07-security-terminal.png) |
| 전체 포트를 모두에게 열지 않음 | inbound는 위의 두 규칙만 사용 | [security 화면](docs/evidence/07-shell-replay/07-security-terminal.png) |
| IAM 사용자/Role 1개·관리자 정책 제외 | 배포는 IAM 사용자 1개. 화면의 연결 정책 2개에 `AdministratorAccess`는 없음 | [사용자 마스킹 IAM 화면](docs/evidence/07-shell-replay/07-iam-policies.png) · 위의 최소 권한 한계 참고 |
| 외부 검증 A/B 중 하나 | **A 선택**: 실제 브라우저 페이지. 추가로 외부 `/health`도 200 | [브라우저](docs/evidence/07-shell-replay/07-external-browser.png) · [health](docs/evidence/07-shell-replay/07-health-browser.png) |
| 권장 micro·Linux·EBS 8~10GiB | 사용자가 더 작은 **t4g.nano** 선택. Amazon Linux 2023 ARM64·암호화 8GiB gp3 | [compute 화면](docs/evidence/07-shell-replay/07-compute-terminal.png) |
| 키 페어 1개 생성·안전 보관 | 이번 실습에서 1개 생성. 개인키는 로컬 0600·폴더 0700·Git 제외 | [생성·재개 TXT](docs/evidence/07-shell-replay/07-resume.txt) |
| 실습 후 자원 정리 | EC2 종료·EBS/ENI 자동 삭제·자동 공인 IP 연결 제거·네트워크/클라우드 키 삭제 | [정리 TXT](docs/evidence/07-shell-replay/07-cleanup.txt) · [정리 후 TXT](docs/evidence/07-shell-replay/07-status-destroyed.txt) |
| EIP·NAT·ELB/ALB·RDS 정리 추적 | **이번 실습에서는 만들지 않음.** 계정 전체에 없다는 뜻은 아님 | [삭제 체크리스트](docs/cleanup-checklist.md) |
| 삭제 후 Billing 확인 권장 | 월별 비용 화면 확보. 반영 지연·최종 청구는 미확인 | [사용자 마스킹 비용 화면](docs/evidence/07-shell-replay/07-billing.png) |

## 쉬운 용어와 통신 흐름

| 이름 | 쉬운 뜻 |
|---|---|
| VPC / Subnet | 내 네트워크 울타리 / 그 안의 작은 구역 |
| Route Table / IGW | 통신이 갈 길을 적은 지도 / 인터넷으로 나가는 문 |
| EC2 / EBS | 빌려 쓰는 컴퓨터 / 그 컴퓨터의 저장 장치 |
| Security Group(SG) | **어떤 통신을 들여보낼지** 정하는 문지기 |
| IAM | **누가 AWS에서 어떤 작업을 할지** 정하는 허가증 |
| Docker / Nginx | 프로그램을 담는 실행 상자 / 웹 페이지를 보내 주는 프로그램 |

**브라우저 → 공인 IP·IGW → public subnet → SG의 80번 문 → EC2의 80번 → Docker의 80번 → Nginx**

돌아가는 통신 길은 route table의 IGW 경로가 맡습니다. 서브넷의 IP 자동 할당 옵션은 꺼 두고, EC2 생성 때 공인 IP를 붙였습니다.

## Docker 보너스

- [실제 `docker ps` Up/healthy 화면](docs/evidence/07-shell-replay/07-verify-terminal.png) + [외부 접속 화면](docs/evidence/07-shell-replay/07-external-browser.png): 필수 2종 확보.
- 포트 연결: **host `0.0.0.0:80` → container `80`**.
- Docker 25.0.18 · Compose v2.39.4. HTTPS 보너스는 하지 않았습니다.

<details>
<summary>▶ 정확한 이미지와 서버 실행 방법</summary>

고정 이미지: `nginx:1.30.6-alpine@sha256:4f7cab9e1cd018f80e67f31e02dc0c6d18560b19504461c4f3dd37e5c63a74c5`

아래는 **당시 서버 안에서 실행한 명령**입니다. 지금 로컬에서 실행하거나 삭제된 서버에 접속하라는 뜻이 아닙니다.

```sh
cd /opt/b6-1 && sudo docker compose up -d
```

[Compose](deploy/compose.yaml) · [Nginx 설정](deploy/nginx.conf) · [UserData](deploy/user-data.sh.tpl) · [Shell renderer](deploy/render-user-data.sh). 기존 앱·이미지 설정·UserData 원본은 바꾸지 않았습니다.

</details>

<details>
<summary>▶ Shell 사용법과 실제 실행 기록</summary>

인증·환경변수 준비와 새 실습 명령은 [scripts/README.md](scripts/README.md)를 봅니다. 현재 완료된 state의 삭제 결과만 확인하는 명령은 다음과 같습니다.

```sh
./scripts/status.sh --state runtime/shell-015-state.json
```

기본 `create`/`destroy`는 계획만 보여 줍니다. 실제 변경에는 `--apply`가 필요합니다. 새 실습은 새 run/state로 시작합니다. 모호한 결과가 나오면 멈추며 같은 자원을 무작정 다시 만들지 않습니다.

- [첫 생성 TXT](docs/evidence/07-shell-replay/07-create.txt) · [남은 단계 재개 TXT](docs/evidence/07-shell-replay/07-resume.txt)
- [FakeAWS 오프라인 검사](docs/evidence/07-shell-replay/07-shell-tests.txt): 실제 AWS·네트워크 호출 0.
- 첫 실행은 빈 SG 뒤 입력 오류에서 멈췄습니다. 수정·독립 검토 후 기존 네트워크를 재사용했습니다. **중단 없이 한 번에 끝난 실행은 아닙니다.**

</details>

<details>
<summary>▶ 문제를 어떻게 찾고 고쳤나요?</summary>

| 순서 | 실제 기록 |
|---|---|
| 증상 | SG 규칙의 DryRun(미리 허가 확인)이 `Invalid JSON received`로 실패 |
| 가설 | 현재 CLI의 해당 stdin 입력 방식이 맞지 않을 수 있음 |
| 검증 | 비민감 HTTP 규칙으로 실패 재현. `--ip-permissions file:///dev/stdin`은 DryRunOperation 확인 |
| 조치 | IP를 파일/명령 인자에 남기지 않고 stdin 배열로 수정. 재개 스크립트의 예상 종료 코드 처리도 수정·검토 |
| 결과 | 기존 network 뒤 규칙·키·EC2만 생성. SSH·내부/외부 200·healthy 확인 후 정리 |
| 예방 | 가짜 AWS 테스트가 실제 입력 배열도 읽도록 보강. 예상 오류와 UNKNOWN을 구별하고 중복 생성 차단 |

[이번 전체 경과](docs/evidence/07-shell-replay/07-run-summary.txt) · [이전 키 저장 문제 보고서](docs/troubleshooting.md)

</details>

<details>
<summary>▶ 과금 요인·정리 순서·IAM/MFA·증빙의 한계</summary>

- 과금 요인: 컴퓨터 사용 시간, EBS 저장 공간, 공인 IPv4, 데이터 전송. 예산 알림은 지출을 강제로 막는 장치가 아닙니다.
- 정리 순서: **EC2 종료 → EBS/ENI/공인 IP 연결 확인 → route table·subnet·SG → IGW → 클라우드 키 → VPC**. 로컬 키·소스·증빙·Git은 남겼습니다.
- [Cost Explorer 관측](docs/evidence/07-shell-replay/07-billing-observation.txt): 2026-10-01~31·월별·필터0·총비용/월평균 US$0.01. 갱신 시각은 화면에 없습니다. 최종 청구·이번 실습 단독 비용·credit 적용을 확정하지 않습니다.
- [IAM 관측](docs/evidence/07-shell-replay/07-iam-observation.txt): `b6-1`과 `SignInLocalDevelopmentAccess`가 직접 연결됨. 경계 미설정. 다른 경로까지 포함한 모든 유효 권한은 증명하지 않습니다.
- [후속 MFA 화면](docs/evidence/07-shell-replay/07-iam-mfa.png)은 콘솔 접근이 “MFA로 활성화됨”을 보여 줍니다. 기기 종류/개수·재로그인·API 키 MFA 강제는 검증하지 않았습니다.
- 실행·정리 7장은 사용자 native 원본입니다. IAM·MFA·Billing 3장은 **사용자 개인정보 마스킹 캡처**입니다. 개인정보를 가린 사진이며, 수정하지 않은 원본 사진과 구분합니다. [원본 출처·해시](docs/evidence/07-shell-replay/07-capture-provenance.txt)
- [촬영 체크리스트](docs/capture-checklist.md) · [삭제 체크리스트](docs/cleanup-checklist.md). 다른 계정 자원·IAM·예산·연락처·로그인 설정은 삭제하지 않았습니다.

</details>

<details>
<summary>▶ 이전 실습 자료 — 원본 보존</summary>

이전 주소 `http://13.124.107.197/`도 해제됐습니다. 다시 요청하지 않습니다.

[05 배포 TXT](docs/evidence/05-ec2-deploy.txt) · [05 JSON](docs/evidence/05-ec2-deploy.json) · [이전 외부 화면](docs/evidence/05-external-http.png) · [06 cleanup](docs/evidence/06-cleanup.txt)

[05 Docker PNG](docs/evidence/05-docker-ps.png)는 실제 stdout을 HTML로 렌더한 과거 자료이며 직접 Terminal 사진이 아닙니다. 이번 07 native 원본과 구분합니다. 이전 그림/문서/소스/키·Git 이력은 보존했습니다.

</details>
