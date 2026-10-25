# 07 실제 화면 캡처 체크리스트

현재 **CLEANED / 실제 런타임·필수 live PNG 6종 확인 완료**다. 실행/정리 7장은 사용자 native Terminal·Chrome 원본이며 Worker 이미지 편집·HTML 재구성은 하지 않았다. IAM/MFA/Billing은 사용자가 개인정보를 이미 마스킹한 별도 제공본이다. 첫 create는 빈 SG 이후 stdin 입력 오류로 멈췄고, 독립 재검토한 수정으로 기존 network를 재사용해 ingress·키·EC2의 남은 단계만 정확히 재개했다. 2026-10-25T11:41:32Z exact run cleanup을 완료했다. cleanup native Terminal PNG도 원본 확인했다.

저장 폴더: `docs/evidence/07-shell-replay/`. 계정 번호/ARN/원시 소스 IP/토큰/인증 URL/키 내용/개인정보가 보이면 촬영하지 않는다. 계정은 마스킹된 CLI 확인 결과만 사용한다.

| 상태 | 실제로 실행할 화면 | 원본 파일 이름 |
|---|---|---|
| DONE — 원본 확인 | `./scripts/status.sh --state runtime/shell-015-state.json --section network` | `07-network-terminal.png` |
| DONE — 원본 확인 | 같은 명령 `--section security`; SSH source는 `PUBLIC_IPV4_MASKED/32`와 일치 boolean만 표시 | `07-security-terminal.png` |
| DONE — 원본 확인 | 같은 명령 `--section compute`; public server IP는 공개 endpoint로 허용 | `07-compute-terminal.png` |
| DONE — healthy·200 확인 | `./scripts/verify.sh --state runtime/shell-015-state.json`; 실제 SSH Docker ps healthy와 localhost root/health HTTP200·outbound 결과 | `07-verify-terminal.png` |
| DONE — 원본 확인 | 실제 새 public URL을 브라우저에서 접속, 주소창과 B6-1 페이지 | `07-external-browser.png` |
| DONE — 원본 확인 | 실제 새 public URL `/health` 화면 | `07-health-browser.png` |
| DONE — 사용자 개인정보 마스킹 원본 | IAM 사용자 연결 정책 화면: 계정/사용자 개인정보 노출 없이 전체 연결 정책·관리자 정책 부재 판단 가능한 경우만. 권한 거부면 그 한계를 기록 | `07-iam-policies.png` |
| DONE — 정리 후 원본 확인 | `./scripts/status.sh --state runtime/shell-015-state.json`의 정확 대상 부재/terminated 화면 | `07-cleanup-terminal.png` |
| DONE — 사용자 마스킹 캡처 | Billing 비용 화면은 개인정보 없이 접근 가능할 때만; 미캡처면 그대로 기록 | `07-billing.png` |

인증/계정 입력을 마친 뒤 Terminal 화면을 clear하고 아래의 read-only 명령만 새 화면에서 실행한다. 로그인 URL/코드/계정 입력이 보이는 화면은 촬영하지 않는다.

먼저 본인 expected 계정·IAM 사용자 환경변수와 `b6-1-iam` 로그인을 로컬에서 설정한다. 인증 코드/URL을 채팅에 보내지 않는다. 단계별 명령은 Shell source 완료 후 실제 상태에 맞춰 다시 안내한다. 필수 live 화면이 PENDING이면 리소스 생성·삭제 진행을 PM과 조율한다. 특히 생성 후 필요한 화면을 확보하기 전에는 cleanup을 시작하지 않는다. 삭제된 endpoint는 다시 접속하지 않는다.

IAM 캡처는 사용자가 계정/ARN을 이미 마스킹한 제공본이며 pristine unedited-native라고 주장하지 않는다. 표시된 정책2개에는 AdministratorAccess가 없으나 전체 유효권한/최소권한 증명은 아니다. 이전 화면은 당시 MFA미설정 상태로 보존했다. 후속 사용자 마스킹 캡처 `07-iam-mfa.png`에는 같은 사용자 콘솔 액세스가 "MFA로 활성화됨"으로 표시된다. MFA 기기 종류/개수·재로그인/API키 MFA강제 여부는 검증하지 않았다.

Billing: Cost Explorer 사용자 개인정보 마스킹 캡처: 2026-10-01~2026-10-31, 월별, 적용필터(0), 총비용 US$0.01/월평균 US$0.01 표시. 화면에 비용 갱신 시각은 없다. 조회 당시 표시만 증명하며 최종 청구·이번 run 단독 비용·크레딧 적용·앞으로 추가 청구 없음은 증명하지 않는다.
