# 설치 → SSH → 삭제 실행 가이드

설치한 Mac에서 사용하는 순서입니다. 다른 컴퓨터에 기존 실행 기록·개인키가 자동으로 생기지는 않습니다.
**오류가 나면 다음 단계로 가지 마세요. 자원·비용 상태를 확인하고 임의로 재실행하지 마세요.**

## 1. Mac · 프로젝트 폴더로 이동

```sh
cd ~/bin/projects/B6-1
```

## 2. Mac · 처음 쓰는 컴퓨터의 준비

터미널(zsh)에서는 파일을 `source`하지 말고 `./excute/install_aws.sh`처럼 실행합니다. AWS CLI v2·jq가 미리 설치돼 있어야 합니다.

```sh
command -v aws jq
```
Intel Mac에서 설치된 도구가 안 보이면 해당 설치 위치를 확인해 현재 터미널에만 PATH를 지정합니다. 임의 `.env`는 읽지 않습니다.

```sh
export PATH="/usr/local/bin:$PATH"
```
계정 번호·IAM 이름은 터미널에서 물을 때 입력해도 됩니다. 다른 명령에서도 쓰려면 `export`가 필요합니다. 아래 예시의 계정 번호는 본인 값으로 바꾸며, 비밀번호·키는 넣지 않습니다.

```sh
export B6_EXPECTED_ACCOUNT='본인_12자리_계정번호'
export B6_IAM_USER='본인_IAM_사용자이름'
# 또는 한 번만: B6_EXPECTED_ACCOUNT='본인_12자리_계정번호' B6_IAM_USER='본인_IAM_사용자이름' ./excute/install_aws.sh
```
`export` 없는 변수는 실행한 스크립트에 전달되지 않습니다. AWS CLI가 PATH 밖에 있으면 `export B6_AWS_BIN='/설치된 경로/aws'`로 정확한 실행 파일만 지정할 수 있습니다. 프로필은 `b6-1-iam`, 리전은 서울로 고정됩니다.
새 Mac에는 로그인·로컬 설치 대상·개인키가 자동 복사되지 않습니다. 이전 서버의 SSH/삭제는 설치한 원래 Mac에서 진행하며, 없어진 대상이나 키를 환경변수로 복구할 수는 없습니다. 새 Mac에 대상 기록이 없을 때의 `삭제 완료`는 아무 자원도 삭제하지 않은 결과이며, AWS 계정 전체가 비었다는 뜻이 아닙니다.

### 로그인 만료 때만 실행

```sh
aws login --profile b6-1-iam --region ap-northeast-2 --remote
```
출력 URL을 직접 시크릿 창에 열고, 코드는 내 터미널에만 입력합니다. 채팅에 보내지 마세요.

## 3. Mac · 설치

```sh
./excute/install_aws.sh
```
필요할 때만 예상 AWS 계정 번호와 IAM 이름 `xifoxy.ru`를 입력합니다. 비밀번호·접근 키 입력은 없습니다.
**`설치 완료`까지 기다리세요.** 자동 설치·패키지 설치·접속 준비 단계를 짧게 표시합니다. 최대 30분 또는 120회까지 기다리며, 설치 로그가 10분간 변하지 않거나 명확한 실패가 있으면 중단합니다. 작은 서버의 첫 설치가 1분 안에 끝난다고 보장하지 않습니다. 새 자원이 생기며 비용이 발생할 수 있습니다.

설치 중 서버 준비 확인만 실패했다면, 원인을 확인한 뒤 기존 대상만 다시 검증할 수 있습니다. 새 자원을 만들지 않습니다.

```sh
./excute/install_aws.sh --verify-only
```
결과 불명·미완료·잠금 상태에서는 실행을 거부합니다. 인증 만료는 위 로그인 명령으로 갱신합니다.

## 4. Mac · SSH 접속

```sh
./excute/ssh_aws.sh
```
CLI 로그인과 설치 검증이 성공해야 합니다. 키 경로·현재 서버 IP는 자동으로 확인합니다.

## 5. EC2 · 서버 안에서 확인

```sh
cd /opt/b6-1
sudo docker compose ps
curl http://localhost/health
```
컨테이너의 `healthy`와 응답 `B6-1 OK`를 확인합니다.

## 6. EC2 · Mac으로 돌아오기

```sh
exit
```

## 7. Mac · 실습 자원 삭제

```sh
cd ~/bin/projects/B6-1
./excute/clean_aws.sh
```
**`삭제 완료`까지 기다리세요.** 해당 설치 대상만 정리하며 로컬 PEM·증빙은 보존합니다.
