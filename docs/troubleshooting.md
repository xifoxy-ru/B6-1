# 실제 트러블슈팅

## SSH 키 생성 성공 후 개인키 저장 실패 (B6-1-011)

- **증상:** AWS 키는 생성됐지만 로컬 개인키 파일이 비어 있어 SSH에 사용할 수 없었다.
- **가설:** AWS 생성 실패보다 로컬 응답 처리 순서의 오류일 수 있었다.
- **검증:** 실제 CreateKeyPair exit 0 뒤 Worker가 응답에 없는 `KeyType`을 읽어 KeyError가 발생했다. 공식 응답 계약, cloud key 존재, local empty/0600, 참조 인스턴스 0개를 확인했다.
- **조치:** 원실패를 보존하고 KeyMaterial write·fsync를 optional metadata 처리보다 먼저 수행하도록 수정했다. 실키 없는 메모리 fixture와 독립 검토를 통과한 뒤, 사용자 명시 승인으로 해당 old key와 자기 빈 파일만 삭제하고 같은 이름으로 한 번 재생성했다.
- **결과:** 현재 키 `key-00e758429d0610364`는 비공개 파일 0600·dir0700·Git ignored이며 공개키 대응 검증 PASS다. 이후 B6-1-012 실제 EC2 SSH 연결도 성공했다.
- **예방:** optional 응답 필드를 필수처럼 가정하지 않는다. 개인키 저장·fsync를 먼저 완료하고 transient write 오류에는 같은 descriptor와 메모리 payload를 유지한다. 생성 호출을 반복하지 않는다. 프로세스/호스트 강제 손실에는 보존 보장이 없다는 한계가 있다.

[원실행·복구 증빙](evidence/04-security-keypair.txt) · [명령/최소 결과](evidence/04-security-keypair.json)

## nano 부트스트랩 설치 지연 관찰 (B6-1-012)

SSH는 성공했지만 cloud-init running·Docker inactive 상태가 이어졌다. 최소 진단에서 `dnf`와 Installing 마커, 여유 메모리 및 OOM 0을 확인했다. 진행 중인 설치로 판단해 재설치·타입 확대·추가 인스턴스 생성 없이 기다렸다. 최종적으로 cloud-init done·Docker healthy·외부 HTTP 200을 확인했다. [배포 증빙](evidence/05-ec2-deploy.txt)에 기록했다. 이 지연 자체를 실패나 OOM으로 꾸미지 않는다.
