# 트러블슈팅

<a id="current"></a>
## 설치 완료 전에 실행한 검증

| 순서 | 실제로 확인한 내용 |
|---|---|
| 증상 | SSH는 연결됐지만 `/opt/b6-1`이 없어 첫 verify가 멈춤 |
| 가설 | 서버 자동 설치가 아직 끝나지 않았을 수 있음 |
| 검증 | 읽기 전용 cloud-init·로그 확인에서 이후 `done`·`B6-1 BOOTSTRAP READY` 확인 |
| 조치 | 재설치·재부팅·EC2 재생성 없이 완료 상태를 확인한 뒤 같은 verify 재실행 |
| 결과 | Docker healthy, localhost `/`·`/health` 200, outbound 200, 외부 root/health 200·원본 파일 일치 |
| 예방 | 준비 중 오류를 최종 장애로 단정하지 말고 상태·로그를 먼저 확인. 무작정 설치나 생성을 반복하지 않음 |

[준비 전 오류](evidence/troubleshooting/verify-before-ready.png) → [설치 READY](evidence/troubleshooting/bootstrap-ready.png) → [검증 성공](evidence/verification/docker-http.png)

자동 설치 완료를 기다린 뒤 같은 검증을 다시 수행해 해결했습니다. 현재 서버는 이미 삭제됐으므로 옛 주소에 진단 명령을 실행하지 않습니다.

## 중단했을 때의 공통 원칙

1. 실패한 명령·상태·사진을 남깁니다. 계정·인증 코드·내 원시 IP·키 내용은 보내지 않습니다.
2. UNKNOWN(결과 불명)이나 촬영 대기 표식이 있으면 같은 생성/삭제를 다시 실행하거나 state를 직접 고치지 않습니다.
3. 남은 자원·비용과 정확한 대상을 확인한 뒤 다음 조치를 정합니다. [명령·촬영 동작](../scripts/README.md#capture)

이전 실습의 중복 오류 기록은 작업 폴더에서 정리했습니다. 이 보고서는 위 실제 오류·설치 완료·성공 화면으로 확인할 수 있는 사례에 집중합니다. 이전 파일은 Git 이력에 남아 있습니다.
