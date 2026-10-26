# 트러블슈팅

<a id="current"></a>
## 현재 기준 016 · 설치 완료 전에 실행한 verify

| 순서 | 실제로 확인한 내용 |
|---|---|
| 증상 | SSH는 연결됐지만 `/opt/b6-1`이 없어 첫 verify가 멈춤 |
| 가설 | 서버 자동 설치가 아직 끝나지 않았을 수 있음 |
| 검증 | 읽기 전용 cloud-init·로그 확인에서 이후 `done`·`B6-1 BOOTSTRAP READY` 확인 |
| 조치 | 재설치·재부팅·EC2 재생성 없이 완료 상태를 확인한 뒤 같은 verify 재실행 |
| 결과 | Docker healthy, localhost `/`·`/health` 200, outbound 200, 외부 root/health 200·원본 파일 일치 |
| 예방 | 준비 중 오류를 최종 장애로 단정하지 말고 상태·로그를 먼저 확인. 무작정 설치나 생성을 반복하지 않음 |

[준비 전 오류](evidence/08-guided-capture/08-08-verify-pending.png) → [설치 READY](evidence/08-guided-capture/08-08-bootstrap-ready.png) → [검증 성공](evidence/08-guided-capture/08-08-verify.png)

이 사례는 **설치 시점 차이**이며 OOM이나 최종 설치 실패를 만들어 낸 기록이 아닙니다. 현재 서버는 이미 삭제됐으므로 옛 주소에 진단 명령을 실행하지 않습니다.

## 중단했을 때의 공통 원칙

1. 실패한 명령·상태·사진을 남깁니다. 계정·인증 코드·내 원시 IP·키 내용은 보내지 않습니다.
2. UNKNOWN(결과 불명)이나 촬영 대기 표식이 있으면 같은 생성/삭제를 다시 실행하거나 state를 직접 고치지 않습니다.
3. 남은 자원·비용과 정확한 대상을 확인한 뒤 다음 조치를 정합니다. [명령·촬영 동작](../scripts/README.md#capture)

<a id="history"></a>
## 과거 기록

다음은 당시의 문제와 해결입니다. 아래 클라우드 키·서버는 현재 실행 중인 자원이 아닙니다.

<details>
<summary>▶ 011 · 클라우드 키 생성 후 로컬 개인키 저장 실패</summary>

| 순서 | 당시 기록 |
|---|---|
| 증상 | AWS 키 생성은 성공했지만 로컬 개인키 파일은 비어 있었음 |
| 가설 | AWS 생성 실패보다 로컬 응답 처리 순서에 문제가 있을 수 있음 |
| 검증 | CreateKeyPair exit0 뒤 응답에 없는 `KeyType`을 읽어 KeyError 발생. 공식 응답 계약·cloud key 존재·빈 로컬 파일·참조 인스턴스 0개 확인 |
| 조치 | 원실패를 보존하고 키 저장·fsync를 선택적 메타데이터 처리보다 먼저 수행하도록 수정. 가짜 데이터 검사·독립 검토 후 사용자 승인으로 해당 키와 자기 빈 파일만 삭제·한 번 재생성 |
| 결과 | 복구 당시 키 `key-00e758429d0610364`와 로컬 파일의 대응 검증 PASS. 이후 012 SSH 성공. 이 cloud key는 013 정리에서 삭제됐고 로컬 파일은 보존 |
| 예방 | 응답의 선택적 필드를 필수로 가정하지 않음. 저장 실패에는 같은 파일 descriptor·메모리 내용을 유지하고 생성을 반복하지 않음. 프로세스/호스트 강제 손실까지 보장하지는 않음 |

[04 실제 TXT](evidence/04-security-keypair.txt) · [04 JSON](evidence/04-security-keypair.json)

</details>

| 실습 | 문제·당시 대응 | 원본 |
|---|---|---|
| 012 | cloud-init running·Docker inactive 동안 dnf/Installing·여유 메모리·OOM0 확인. 재설치·사양 확대 없이 기다린 뒤 healthy/HTTP200 확인. 지연을 장애로 꾸미지 않음 | [05 배포 TXT](evidence/05-ec2-deploy.txt) |
| 013 | 종료 후 assertion·키 typedNotFound 코드 차이로 안전 중단. 원실패를 보존하고 남은 전용 실행을 재검토해 진행, terminate 중복 없음 | [06 cleanup TXT](evidence/06-cleanup.txt) · [JSON](evidence/06-cleanup.json) |
| 015 | ingress stdin 입력 오류로 빈 SG 뒤 중단. 다른 stdin 방식 검증·재개 코드 검토 후 기존 network를 재사용. 중단 없는 한 번의 실행은 아니었음 | [07 관측 요약](evidence/07-shell-replay/07-run-summary.txt) |

요약 TXT는 과거 기록을 찾는 보조 자료이며 새 실행 증거가 아닙니다. [전체 증빙 구분](evidence-guide.md#history)
