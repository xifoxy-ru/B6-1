# 증빙 안내

**현재 결과는 016 실습입니다.** 아래 19장은 사용자가 실제 Terminal·브라우저를 촬영한 원본입니다. 사진의 바이트·이름·경로를 바꾸지 않았습니다. [확인 범위와 한계](../README.md#limits)는 README에 모았습니다.

<a id="current-captures"></a>
## 현재 016 사진 19장

| 단계 | 실제 사진 | 확인할 내용 |
|---|---|---|
| 생성 1 | [VPC](evidence/08-guided-capture/08-01-vpc.png) | VPC 생성 결과 |
| 생성 2 | [서브넷](evidence/08-guided-capture/08-02-subnet.png) | CIDR·서울 AZ |
| 생성 3 | [IGW·라우팅](evidence/08-guided-capture/08-03-routing.png) | 연결·기본 경로·서브넷과 라우팅표의 연결관계 |
| 생성 4 | [보안그룹·키](evidence/08-guided-capture/08-04-security-key.png) | HTTP80·SSH22 제한, 키 저장·대응 확인 |
| 생성 5 | [EC2](evidence/08-guided-capture/08-05-ec2-create.png) | 한 대 생성·부트스트랩 준비 중 |
| 상태 | [네트워크](evidence/08-guided-capture/08-06-network-status.png) · [EC2·디스크](evidence/08-guided-capture/08-07-compute-status.png) | 사용 중인 경로·8GiB 암호화 디스크·IMDSv2 |
| 설치 경과 | [verify 준비 전](evidence/08-guided-capture/08-08-verify-pending.png) · [READY](evidence/08-guided-capture/08-08-bootstrap-ready.png) | 완료 전 오류와 이후 설치 완료를 구분 |
| 검증 | [SSH·Docker·HTTP](evidence/08-guided-capture/08-08-verify.png) | healthy·localhost root/health 200·outbound 200 |
| 외부 확인 | [브라우저 A](evidence/08-guided-capture/08-09-external-browser.png) · [health](evidence/08-guided-capture/08-09b-health-browser.png) | 실제 페이지·B6-1 OK |
| 정리 1 | [EC2/EBS/ENI part1](evidence/08-guided-capture/08-10-terminate-part-1.png) · [part2](evidence/08-guided-capture/08-10-terminate-part-2.png) | 종료·자동 삭제·공인 IP 연결 제거 |
| 정리 2 | [라우팅](evidence/08-guided-capture/08-11-route-cleanup.png) | 연결·경로·직접 만든 라우팅표 삭제 |
| 정리 3 | [서브넷·SG](evidence/08-guided-capture/08-12-subnet-sg-cleanup.png) | 삭제 결과 |
| 정리 4 | [인터넷 게이트웨이·AWS에 등록한 키](evidence/08-guided-capture/08-13-gateway-key-cleanup.png) | 분리·삭제, 로컬 키는 보존 |
| 정리 5 | [VPC·정확 대상 부재](evidence/08-guided-capture/08-14-cleanup.png) | 마지막 VPC 삭제·8종 자원이 없음을 확인 |
| 최종 확인 | [DESTROYED status](evidence/08-guided-capture/08-15-status-destroyed.png) | 미완료 작업 없음·추가 삭제 없음·서버 재접속 없음 |

각 생성·삭제 그룹은 사진을 저장한 뒤 Enter로 넘어갔습니다. 긴 종료 출력은 part1/2로 나눴습니다. [촬영 옵션의 동작](../scripts/README.md#capture)은 실행 안내에서 설명합니다.

- 앱의 `STATIC PAGE · 012`는 기존 화면 문구이며 실습 번호가 아닙니다.
- 해제된 `3.34.255.78`에는 HTTP·SSH 요청을 하지 않습니다.
- [08-summary.txt](evidence/08-guided-capture/08-summary.txt)는 **사진 관측 요약**, [08-provenance.txt](evidence/08-guided-capture/08-provenance.txt)는 **출처·해시 기록**, [08-offline-tests.txt](evidence/08-guided-capture/08-offline-tests.txt)는 **AWS 호출을 흉내 낸 로컬 테스트 출력**입니다. 사진이나 새로운 실제 AWS 검사로 대신 해석하지 않습니다.

<a id="history"></a>
## 이전 기록과 보조 자료

이전 원본은 경로와 바이트 그대로 남겼습니다. 당시의 “현재”·키·주소·금액은 오늘의 상태를 뜻하지 않습니다.

| 기록 | 원본·용도 |
|---|---|
| 015 실제 실행·정리 | [07 요약](evidence/07-shell-replay/07-run-summary.txt) · [출처](evidence/07-shell-replay/07-capture-provenance.txt) · [명령/TXT 모음](evidence/07-shell-replay/) |
| 015 네트워크·보안·EC2·검증 | [network](evidence/07-shell-replay/07-network-terminal.png) · [security](evidence/07-shell-replay/07-security-terminal.png) · [compute](evidence/07-shell-replay/07-compute-terminal.png) · [verify](evidence/07-shell-replay/07-verify-terminal.png) |
| 015 외부 확인·정리 | [브라우저](evidence/07-shell-replay/07-external-browser.png) · [health](evidence/07-shell-replay/07-health-browser.png) · [cleanup](evidence/07-shell-replay/07-cleanup-terminal.png) |
| 015 IAM·MFA | [정책 목록](evidence/07-shell-replay/07-iam-policies.png) · [이후 MFA 화면](evidence/07-shell-replay/07-iam-mfa.png) · [관측 범위](evidence/07-shell-replay/07-iam-observation.txt) |
| 015 Billing | [사용자 마스킹 사진](evidence/07-shell-replay/07-billing.png) · [관측 범위](evidence/07-shell-replay/07-billing-observation.txt) |
| 012 배포·013 정리 | [05 배포 TXT](evidence/05-ec2-deploy.txt) · [05 JSON](evidence/05-ec2-deploy.json) · [06 cleanup TXT](evidence/06-cleanup.txt) · [06 JSON](evidence/06-cleanup.json) |
| 이전 구조·문제 해결 | [아키텍처 PNG](architecture.png) · [SVG](architecture.svg) · [트러블슈팅의 과거 기록](troubleshooting.md#history) |

015의 실행·정리 사진 7장은 실제 화면입니다. IAM·MFA·Billing 3장은 사용자가 개인정보를 가린 제공본입니다. 정책 목록에 AdministratorAccess가 보이지 않는 것과 전체 최소 권한 증명은 다릅니다. MFA 화면은 당시 콘솔의 활성 상태만 보여 주며 기기 종류·재로그인·API 키 MFA 강제를 검증하지 않았습니다.

015 Cost Explorer의 US$0.01은 2026-10-01~31·월별·필터0의 당시 표시입니다. 갱신 시각은 없으며 016 최종 청구·실습 단독 비용·크레딧 적용을 증명하지 않습니다.

[05 외부 사진](evidence/05-external-http.png)은 당시 브라우저 기록입니다. [05 Docker PNG](evidence/05-docker-ps.png)는 실제 stdout를 HTML로 렌더한 **과거 보조 자료**이며 직접 Terminal 사진이 아닙니다. 현재 08 사진과 구분합니다. 이전 주소 `13.124.107.197`·`43.203.227.198`도 해제됐으므로 다시 접속하지 않습니다.
