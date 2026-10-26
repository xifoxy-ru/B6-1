# B6-1 · AWS 웹 서버 실습

**생성 → 단계별 사진 저장 → 웹 접속 확인 → 삭제까지 완료했습니다.**

현재 결과는 `capture-016-20261026` 실습의 **CLEANED** 상태입니다. 서울의 EC2 한 대에서 Docker·Nginx를 실행했고, 사용자 Terminal·브라우저 사진 19장을 남겼습니다.

| 보고 싶은 내용 | 안내 |
|---|---|
| 실제 사진·명세별 증거 | [증빙 안내](docs/evidence-guide.md) |
| 명령 사용법·단계별 촬영 | [실행·운영 안내](scripts/README.md) |
| 오류와 해결 과정 | [트러블슈팅](docs/troubleshooting.md) |
| 무엇을 삭제했는지 | [삭제 체크리스트](docs/cleanup-checklist.md) |

## 대표 결과

외부 확인은 **방법 A: 브라우저 접속**을 선택했습니다. 당시 주소는 `http://3.34.255.78/`이며, **이미 해제됐으므로 다시 접속하지 마세요.**

![삭제 전에 실제 브라우저에서 확인한 Nginx 화면](docs/evidence/08-guided-capture/08-09-external-browser.png)

*삭제 전에 촬영한 사진입니다. 현재 실행 중인 서버는 아닙니다.*

## 필수 제출물 4개

| 제출물 | 바로 보기 |
|---|---|
| 구성·통신 흐름 그림 | [아키텍처 PNG](docs/architecture.png) |
| 외부 접속 증명 | [브라우저 사진](docs/evidence/08-guided-capture/08-09-external-browser.png) |
| 문제 해결 보고서 | [증상 → 확인 → 조치 → 결과](docs/troubleshooting.md#current) |
| 자원 정리 기록 | [삭제 대상·완료 증거](docs/cleanup-checklist.md) |

<a id="limits"></a>
## 확인한 범위와 남은 한계

| 항목 | 정확한 상태 |
|---|---|
| 최소 권한 | **완전히 충족하지 못했습니다.** 정책은 서울의 다른 자원과 예산·연락처 작업도 허용합니다. |
| 루트 계정 미사용 | 배포 CLI는 정해진 IAM 사용자로 확인했습니다. 계정 관리까지 포함한 전 과정의 루트 미사용은 입증하지 못했습니다. |
| 무료 사용·크레딧 | 실제 적용 여부 미확인. 작은 서버도 비용이 생길 수 있습니다. |
| 비용 화면 | 이전 015의 US$0.01 화면만 보존했습니다. 이번 016의 최신·최종 청구액은 미확인입니다. |
| 구조 그림 | 같은 구성의 이전 자원 번호가 들어 있습니다. 이번 번호는 사진과 삭제 체크리스트에서 확인합니다. |

<details>
<summary>▶ 명세와 실제 결과 요약</summary>

| 요구 | 결과·증거 |
|---|---|
| 서울·Linux·EC2 한 대·EBS 8~10GiB | Amazon Linux 2023 ARM64, 사용자 선택 t4g.nano, 암호화 8GiB gp3. micro는 권장 예시입니다. [EC2 사진](docs/evidence/08-guided-capture/08-07-compute-status.png) |
| VPC·public subnet·IGW·인터넷 경로 | 각 1개, `0.0.0.0/0 → IGW`, 명시적 서브넷 연결. [네트워크 사진](docs/evidence/08-guided-capture/08-06-network-status.png) |
| HTTP80 공개·SSH22 내 IP만·전체 포트 개방 금지 | 두 inbound 규칙만 사용, SSH는 당시 IP `/32`. [보안·키 사진](docs/evidence/08-guided-capture/08-04-security-key.png) |
| SSH·Nginx·EC2 내부 HTTP200·outbound | 실제 SSH, localhost `/`·`/health` 200, 인터넷 HTTPS 요청 200. [검증 사진](docs/evidence/08-guided-capture/08-08-verify.png) |
| 외부 확인 A/B 중 하나 | A 선택. 추가로 [외부 health](docs/evidence/08-guided-capture/08-09b-health-browser.png)도 확인 |
| 키 1개 안전 보관·자원 정리 | 이번 실행에서 키 1개 생성. 로컬 키 보존, 클라우드 자원 삭제. [체크리스트](docs/cleanup-checklist.md) |
| Docker 보너스 | [docker ps Up/healthy](docs/evidence/08-guided-capture/08-08-verify.png) + [외부 접속](docs/evidence/08-guided-capture/08-09-external-browser.png) 2종, host `0.0.0.0:80 → container 80`. [이미지·실행 명령](scripts/README.md#configuration) |
| HTTPS 보너스 | 미구현 |

SG는 **들어올 통신**, IAM은 **AWS에서 할 작업**을 허용합니다. 통신은 브라우저 → IGW·public subnet → SG80 → EC2 host80 → Docker80 → Nginx로 이어집니다. [용어·과금·정리 순서](scripts/README.md#basics)를 참고하세요.

</details>
