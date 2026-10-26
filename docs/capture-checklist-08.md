# 08 단계별 실제 촬영 — 준비 중

**완료 — 사용자 Terminal에서 단계별 생성·검증·삭제 사진 19장을 확보했습니다.** 최종 state는 DESTROYED이며 pending/촬영 대기 표식이 없습니다. 사진은 [08 전용 폴더](evidence/08-guided-capture/)로 원본 바이트 그대로 옮겼습니다. 아래 이름은 실제 저장된 사진입니다.

## 진행 규칙

- `--capture`는 **실제 Terminal 입력과 출력**이 모두 연결돼야 합니다. `| tee`, 파일 입력/출력으로 실행하면 변경 전에 거부합니다.
- 각 그룹의 명령/결과가 실제로 실행된 뒤 한글 제목·PNG 이름·다음 작업이 나옵니다.
- 사진을 저장하고 PM 확인을 받은 뒤 **빈 Enter 한 번**만 누릅니다. 미리 여러 Enter를 붙여넣지 마세요.
- 화면을 자동으로 지우지 않습니다. 긴 출력은 스크롤해 `-part1.png`, `-part2.png`로 나눠 모두 저장합니다.
- EOF/Ctrl-C는 다음 그룹으로 넘어가지 않습니다. state와 촬영 대기 표식이 남습니다. **같은 create/destroy를 다시 실행하지 말고** 부분 상태·남은 비용을 PM에게 알려 검토받습니다.
- 계정/ARN/내 원시 IP/로그인 URL·코드/키 내용/개인정보가 보이면 촬영하지 않습니다. 키는 보내거나 Git에 넣지 않습니다.
- 실제 사진은 `docs/evidence/08-guided-capture/`에 보존했습니다. HTML 재구성·가짜 Terminal 화면은 사용하지 않습니다.

## 생성 명령의 다섯 정지 지점

| 순서 | 한글 촬영 제목 | 파일 이름 | Enter 뒤에 하는 일 |
|---|---|---|---|
| 1 | AWS VPC 생성 결과 | `08-01-vpc.png` | subnet 생성 |
| 2 | AWS 퍼블릭 서브넷 생성 결과 | `08-02-subnet.png` | IGW·라우팅 구성 |
| 3 | AWS 인터넷 게이트웨이와 라우팅 구성 결과 | `08-03-routing.png` | SG·키 생성 |
| 4 | AWS 보안그룹 및 SSH 키 생성 결과 | `08-04-security-key.png` | EC2 생성, 여기부터 서버 비용 발생 |
| 5 | AWS EC2 생성 결과 | `08-05-ec2-create.png` | create 명령 종료. 새 create 금지 |

그룹 4 사진에는 HTTP80/내 IP SSH22 규칙, 키 ID·타입·권한·대응 확인만 남깁니다. 개인키·공개키 내용은 출력하지 않습니다.

## 서버 준비 후 별도 확인

| 실제 명령/화면 | 계획한 사진 | 확인할 내용 |
|---|---|---|
| `status.sh --section network` | `08-06-network-status.png` | subnet·IGW·active 경로·명시적 연결 |
| `status.sh --section compute` | `08-07-compute-status.png` | 새 EC2·8GiB 암호화 디스크·새 공인 주소 |
| `verify.sh` | `08-08-verify.png` | 실제 SSH·docker ps Up/healthy·EC2 localhost `/`와 `/health` 200·outbound 200 |
| 새 주소의 실제 브라우저 `/` | `08-09-external-browser.png` | 주소창·웹 페이지 |
| 새 주소의 실제 브라우저 `/health` | `08-09b-health-browser.png` | 주소창·B6-1 OK |

기본 명령에는 PM이 알려 준 **새 state 경로**를 붙입니다. bootstrap 준비 중이면 PENDING으로 기록하고 재설치·재생성하지 않습니다. 필수 live 사진이 남아 있으면 cleanup을 시작하지 않습니다.

## 삭제 명령의 다섯 정지 지점

**필수 사진 저장 → 실제 새 자원 refs 삭제계획 독립 PASS → PM 안내** 순서 뒤에만 실행합니다.

| 순서 | 한글 촬영 제목 | 파일 이름 | Enter 뒤에 하는 일 |
|---|---|---|---|
| 10 | AWS EC2 종료 및 EBS·ENI·공인 IP 연결 제거 | `08-10-terminate-part-1.png`, `08-10-terminate-part-2.png` | custom RT 정리 |
| 11 | AWS 라우팅 테이블 정리 결과 | `08-11-route-cleanup.png` | subnet·SG 정리 |
| 12 | AWS 서브넷 및 보안그룹 정리 결과 | `08-12-subnet-sg-cleanup.png` | IGW·cloud key 정리 |
| 13 | AWS IGW 및 클라우드 SSH 키 정리 결과 | `08-13-gateway-key-cleanup.png` | VPC 마지막 삭제 |
| 14 | AWS 실습 자원 정리 완료 확인 | `08-14-cleanup.png` | 삭제 명령 종료·read-only status 확인 |

종료 뒤 해제된 IP/HTTP에 다시 접속하지 않습니다. 로컬 old/new 키·소스·사진·Git은 보존합니다. 권장 IAM/Billing 화면은 개인정보를 가린 사용자 제공 사진으로 별도 구분하며, 권한·최종 비용을 과장하지 않습니다.

## 추가 실제 기록

- [verify 준비 전](evidence/08-guided-capture/08-08-verify-pending.png) → [bootstrap READY](evidence/08-guided-capture/08-08-bootstrap-ready.png) → [verify 성공](evidence/08-guided-capture/08-08-verify.png): 재설치/자원 재생성은 하지 않았습니다.
- [최종 정리 후 status](evidence/08-guided-capture/08-15-status-destroyed.png): 8종 정확 typedNotFound·DESTROYED_NOOP, endpoint 요청 없음.
- [관측 요약](evidence/08-guided-capture/08-summary.txt) · [원본 출처·해시](evidence/08-guided-capture/08-provenance.txt). 사진은 실제 stdout의 대체 그림이 아닙니다.
- 해제된 `3.34.255.78`에는 HTTP/SSH/기타 probe를 다시 하지 않습니다. 이전 IAM/MFA/Billing 사진은 015 당시의 기록이며 이번 비용·최소 권한을 새로 증명하지 않습니다.
