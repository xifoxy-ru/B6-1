# 증빙 안내

이번 실습은 **직접 생성 → 접속 확인 → 삭제**까지 마쳤습니다. 실제 Terminal·브라우저 사진 19장을 작업별로 모았습니다. 사진 내용은 그대로 두고 이름과 폴더만 정리했습니다.

<a id="current-captures"></a>
## 생성과 접속 확인

| 단계 | 사진 | 확인할 내용 |
|---|---|---|
| 네트워크 생성 | [VPC](evidence/provision/vpc-created.png) · [서브넷](evidence/provision/subnet-created.png) · [인터넷 연결](evidence/provision/internet-routing.png) | 네트워크 주소·서울 가용 영역·인터넷 경로·서브넷 연결 |
| 보안과 서버 생성 | [보안그룹·키](evidence/provision/security-group-key.png) · [EC2](evidence/provision/ec2-created.png) | HTTP80 공개·SSH22 내 IP만·키 저장·EC2 한 대 생성 |
| 구성 확인 | [네트워크 상태](evidence/verification/network-status.png) · [서버·디스크](evidence/verification/compute-status.png) | 정상 경로·8GiB 암호화 디스크·서버 실행 상태 |
| 설치 경과 | [완료 전 오류](evidence/troubleshooting/verify-before-ready.png) · [설치 완료](evidence/troubleshooting/bootstrap-ready.png) | 자동 설치가 끝나기 전과 후의 차이 |
| 서버 검증 | [Docker·HTTP](evidence/verification/docker-http.png) | Up·healthy, 내부 `/`·`/health` 200, 인터넷 요청 200 |
| 외부 접속 | [브라우저 페이지](evidence/verification/browser-page.png) · [상태 확인 페이지](evidence/verification/browser-health.png) | 실제 페이지·B6-1 OK |

앱의 `STATIC PAGE · 012`는 기존 화면 문구이며 이번 실행 번호가 아닙니다. 원래 사진의 촬영 파일명과 지금 보관 이름은 다르지만 같은 사진입니다. 자세한 [문제 해결 과정](troubleshooting.md#current)도 남겼습니다.

## 삭제와 최종 확인

| 단계 | 사진 | 확인할 내용 |
|---|---|---|
| 서버 종료 | [출력 앞부분](evidence/cleanup/instance-termination-part-1.png) · [뒷부분](evidence/cleanup/instance-termination-part-2.png) | EC2 종료·디스크와 네트워크 인터페이스 자동 삭제·공인 IP 연결 제거 |
| 네트워크 정리 | [라우팅표](evidence/cleanup/routes-deleted.png) · [서브넷·보안그룹](evidence/cleanup/subnet-security-group-deleted.png) | 연결·경로와 직접 만든 자원 삭제 |
| 출입구·키 정리 | [IGW·AWS 키](evidence/cleanup/gateway-cloud-key-deleted.png) | 인터넷 연결 분리·삭제, AWS에 등록한 키 삭제 |
| 마지막 삭제 | [VPC 삭제](evidence/cleanup/vpc-deleted.png) | VPC 삭제·8종 자원이 없음을 확인 |
| 종료 후 확인 | [최종 상태](evidence/cleanup/final-status.png) | 미완료 작업 없음·추가 삭제 없음·서버 재접속 없음 |

[삭제 체크리스트](cleanup-checklist.md)는 실제 자원 번호와 완료 범위를 정리합니다. 해제된 주소 `3.34.255.78`에 다시 HTTP·SSH 요청을 하지 않습니다. 삭제 완료가 계정 전체 자원 부재나 청구 0을 뜻하지는 않습니다.

<a id="account"></a>
## 계정 설정 보충 자료 · 2026년 10월 25일

아래 세 장은 **사용자가 개인정보를 가린 제공본**입니다. 위 실행 사진과 구분하며, 이후 모든 설정이 그대로라는 증거로 사용하지 않습니다.

| 자료 | 사진에서 확인한 범위 |
|---|---|
| [IAM 정책 목록](evidence/account/iam-policies-2026-10-25.png) | b6-1·SignInLocalDevelopmentAccess 두 정책 표시. AdministratorAccess는 목록에 없지만 전체 유효 권한이나 최소 권한을 증명하지는 않음 |
| [MFA 설정 후 화면](evidence/account/iam-mfa-2026-10-25.png) | 콘솔 접근이 MFA로 활성화된 상태. 기기 종류·개수·재로그인이나 API 키의 MFA 강제는 검증하지 않음 |
| [Cost Explorer](evidence/account/cost-explorer-2026-10-25.png) | 2026-10-01~31 월별·필터 0·총비용/월평균 US$0.01 표시. 갱신 시각 미표시. 최신 실습 단독 비용·최종 청구·크레딧 적용 증거가 아님 |

이전 실행의 중복 사진·TXT·JSON, 사진 내용을 반복하던 요약과 해시 기록은 작업 폴더에서 정리했습니다. 과거 파일은 Git 이력에 남아 있습니다. 현재 결과는 위 원본 화면과 [README의 확인 범위](../README.md#limits)를 기준으로 봐 주세요. 아키텍처 그림에는 이전 자원 번호가 남아 있지만 같은 논리 구성을 설명합니다.
