# SMUBoard — 재난현장 조사

세명대학교 재난안전학과 재난현장 조사 앱. 현장사진에 조사 보드와 브이월드 약도를
합성하고, 현황조사표를 HWPX로 만들어 구글 드라이브에 저장한다.

모바일 웹(Flutter Web)으로 동작하며 GitHub Pages에 배포한다.

## 흐름

```
구글 로그인 → 조사 목록 → 조사 개요 → 현장 촬영 → 현황조사표 → 검토·제출
```

촬영한 사진은 합성 직후 기기에 보관되고, 통신이 되는 대로 드라이브에 올라간다.
모바일 웹은 탭이 백그라운드에서 정리되면 메모리의 사진이 사라지므로, 가장 잃기 쉬운
것을 가장 오래 들고 있지 않기 위해서다. 제출 단계에서는 나머지 세 산출물만 만든다.

## 오프라인 촬영

통신이 끊긴 현장에서도 촬영을 계속할 수 있다.

- 합성이 끝난 사진을 **IndexedDB에 먼저 보관하고**, 업로드가 확인된 뒤에 지운다.
  순서가 반대면 실패한 사진이 사라진다. localStorage는 5MB 남짓이라 사진 한 장에도
  넘치므로 쓰지 않는다.
- 브라우저의 `online` 이벤트, 앱 시작, 사용자의 "지금 올리기"에 재시도한다.
  자동 재시도는 20초에서 시작해 실패할수록 최대 10분까지 물러난다.
- 축소본은 업로드 후에도 남긴다. 탭을 새로고침해도 목록의 사진이 사라지지 않고,
  제출 시 HWPX 조사표에 넣을 사진이 확보된다. 조사 제출이 끝나면 함께 정리한다.
- 화면은 대기를 **실패가 아니라 보관됨**으로 표시한다. 통신이 없는 것은 사용자
  잘못이 아니고, 사진은 실제로 안전하게 남아 있다.

보관본이 사라진 경우(브라우저 사이트 데이터 삭제 등)에만 "다시 촬영" 안내가 뜬다.

동작 확인용 개발 진입점이 둘 있다. 배포 번들에는 들어가지 않는다.

```bash
# IndexedDB 보관소 자체 (저장·복구·삭제·용량)
flutter run -d chrome -t lib/dev/offline_check.dart

# 오프라인 촬영 시나리오 전체. 1단계 실행 → 페이지 새로고침 → 2단계 자동 진행
flutter run -d chrome -t lib/dev/offline_capture_check.dart --dart-define=VWORLD_KEY=...
```

`offline_capture_check`는 드라이브만 가짜로 두고 IndexedDB·큐·합성 파이프라인은
실제 코드를 그대로 쓴다. 1단계에서 오프라인으로 두 장을 찍어 보관되는지 보고,
브라우저를 진짜 새로고침한 뒤 2단계에서 복구·자동 업로드·보관본 정리를 검사한다.

## 산출물

| 산출물 | 형식 | 위치 |
|---|---|---|
| 현황조사표 | `.hwpx` | 조사 폴더 |
| 현장사진 | `.jpg` (보드 + 약도 합성) | 조사 폴더 |
| 조사 원본 데이터 | `survey.json` | 조사 폴더 |
| 조사 집계표 | 구글 시트 | 루트 폴더에 1개, 조사마다 1행 |

```
내 드라이브/
└─ SMUBoard 재난조사/
   ├─ 2026-08-29_○○천 제방 유실/
   │  ├─ 현황조사표_2026-08-29_○○천 제방 유실.hwpx
   │  ├─ survey.json
   │  └─ 사진_01_제방 유실부 전경.jpg
   └─ 조사집계표
```

> 구글 문서는 HWPX를 열거나 변환하지 못한다. 드라이브에 `.hwpx` 바이너리로 올라가고,
> 열람은 한컴오피스 또는 한컴독스에서 한다.

## 실행

```bash
flutter pub get
flutter run -d chrome \
  --dart-define=VWORLD_KEY=... \
  --dart-define=GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com
```

약도만 따로 확인할 때:

```bash
flutter run -d chrome -t lib/dev/sketch_preview.dart --dart-define=VWORLD_KEY=...
```

## 배포 전 설정

배포본이 동작하려면 구글과 브이월드 두 곳에 등록이 필요하다. 키 값은 저장소
Secret으로만 주입한다(`Settings → Secrets and variables → Actions`).

| Secret | 없으면 |
|---|---|
| `GOOGLE_WEB_CLIENT_ID` | 로그인 화면에서 더 진행되지 않는다 |
| `VWORLD_KEY` | 약도가 빠진 채로 사진이 합성된다 |

클라이언트 웹앱이라 두 값 모두 빌드 결과에 남는다. 실제 보호는 아래의 도메인
등록으로 한다 — Secret은 저장소 소스와 커밋 이력에 키를 남기지 않기 위한 것이다.

### 구글 설정

Google Cloud 콘솔(<https://console.cloud.google.com>)에서 순서대로 한다.

**1. 프로젝트 만들기**
사용할 프로젝트를 하나 고르거나 새로 만든다.

**2. API 사용 설정** — `API 및 서비스 → 라이브러리`

- **Google Drive API**
- **Google Sheets API** (집계표를 쓰므로 함께 필요하다)

빠뜨리면 로그인은 되지만 업로드에서 `403 API has not been used` 오류가 난다.

**3. OAuth 동의 화면** — `API 및 서비스 → OAuth 동의 화면`

- User Type: 학교 계정만 쓸 거면 **내부**, 개인 구글 계정도 받으려면 **외부**
- 앱 이름 · 사용자 지원 이메일 · 개발자 연락처를 채운다
- 범위(스코프)에 `.../auth/drive.file` 추가
- **외부**로 만들었고 게시 상태가 *테스트*라면, 로그인할 계정을 **테스트 사용자**에
  모두 등록해야 한다. 등록하지 않은 계정은 로그인 자체가 거부된다

`drive.file`은 앱이 만든 파일에만 접근하는 비민감 스코프라, 민감·제한 스코프처럼
별도 보안 심사를 요구하지 않는다. 사용 인원이 늘면 테스트 상태로 두지 말고 게시
상태를 프로덕션으로 올리는 편이 낫다(테스트 상태의 토큰은 주기적으로 만료된다).

**4. 클라이언트 ID 만들기** — `API 및 서비스 → 사용자 인증 정보 → 사용자 인증 정보 만들기 → OAuth 클라이언트 ID`

- 애플리케이션 유형: **웹 애플리케이션**
- **승인된 자바스크립트 원본**에 아래를 추가한다. 경로(`/smuboard/`)는 넣지 않는다 —
  원본은 스킴 + 호스트 + 포트까지다.

  ```
  https://smuds-m.github.io
  http://localhost:8099      ← 로컬에서 돌려볼 때만
  ```

- **승인된 리디렉션 URI**는 비워 둬도 된다. 이 앱은 Google Identity Services
  방식이라 리디렉션을 쓰지 않는다.

만들면 `...apps.googleusercontent.com` 형태의 클라이언트 ID가 나온다. 클라이언트
보안 비밀번호(secret)는 이 앱에서 쓰지 않는다.

**5. 저장소에 등록하고 재배포**

```bash
gh secret set GOOGLE_WEB_CLIENT_ID -R SMUDS-m/smuboard
gh workflow run deploy.yml -R SMUDS-m/smuboard
```

로컬에서 돌려볼 때는 `--dart-define`으로 같은 값을 넘긴다.

```bash
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com
```

### 브이월드 설정

브이월드 오픈API(<https://www.vworld.kr>)에서 인증키를 발급받고, **서비스
URL(도메인)** 에 배포 주소를 등록한다.

```
smuds-m.github.io
```

등록하지 않으면 타일 요청이 이미지 대신 오류 XML을 돌려주고, 앱은 약도 없이
합성을 계속한다(사진 자체는 정상 저장된다).

### 안 될 때

| 증상 | 원인 |
|---|---|
| 로그인 창이 뜨자마자 닫힘 | 승인된 자바스크립트 원본에 접속 주소가 없음. 경로를 붙여 넣지 않았는지 확인 |
| `앱이 차단되었습니다` | 게시 상태가 *테스트*인데 로그인 계정이 테스트 사용자에 없음 |
| 업로드에서 403 | Drive API 또는 Sheets API 사용 설정이 안 됨 |
| 사진은 되는데 약도만 없음 | 브이월드 키 미주입 또는 도메인 미등록 |

## OAuth 스코프

`drive.file` 하나만 쓴다. 앱이 만든 파일에만 접근하는 스코프라 사용자의 기존 드라이브를
볼 수 없고, 구글 시트 API도 이 스코프를 받아들여 `spreadsheets`를 따로 요구하지 않는다.
구글의 민감·제한 스코프 심사 대상에서 벗어난다.

## HWPX 템플릿

`assets/templates/현황조사표.hwpx`는 ZIP + OWPML XML이다. 앱은 브라우저에서
`Contents/section0.xml`의 `{{키}}`를 값으로 바꾸고 `BinData/`의 자리표시 그림
바이트를 실제 사진으로 갈아 끼운 뒤 다시 압축한다. 그림을 새로 삽입하지 않고
바이트만 교체하므로 크기·위치·도형 XML을 손대지 않는다.

사진칸은 6장이다. 그보다 많이 찍으면 앞의 6장만 조사표에 들어가고, 전체는 드라이브
폴더에 그대로 남는다.

실제 기관 양식으로 바꿀 때는 그 양식에 같은 `{{키}}`를 넣고 자리표시 그림을 6장 심어
이 파일을 교체하면 된다. Dart 코드는 고치지 않아도 된다. 치환 키 목록은
`Survey.toTemplateValues()`에 있다.

## 구조

```
lib/
├─ models/          Survey · SurveyPhoto · BoardData · 선택지 enum
├─ services/
│  ├─ google_auth_service.dart   로그인, API 클라이언트 발급
│  ├─ drive_service.dart         폴더·업로드·시트 집계
│  ├─ vworld_service.dart        약도 타일 스티칭, 역지오코딩
│  ├─ board_composer.dart        원본 해상도 합성 → JPEG
│  ├─ photo_pipeline.dart        촬영 1장의 전 과정
│  ├─ upload_queue.dart          오프라인 보관 · 재시도 · 대기 상태
│  ├─ offline/                   IndexedDB 보관소, 연결 감시 (웹/네이티브 분기)
│  ├─ hwpx_builder.dart          HWPX 템플릿 치환
│  ├─ submit_service.dart        산출물 4종 오케스트레이션
│  ├─ jsonp/                     CORS 없는 API용 (웹/네이티브 분기)
│  └─ download/                  브라우저 다운로드 (웹/네이티브 분기)
├─ widgets/board_painter.dart    화면 미리보기와 최종 합성의 단일 진입점
└─ screens/                      로그인 → 목록 → 개요 → 촬영 → 조사표 → 제출
```

`BoardPainter`는 미리보기(화면 크기)와 최종 합성(원본 해상도)에서 같은 코드를 쓴다.
위젯을 캡처하지 않고 캔버스에 직접 그리므로 화면 해상도에 결과가 묶이지 않는다.

## 브이월드 참고

- WMTS 타일은 `Access-Control-Allow-Origin: *`이라 브라우저 캔버스에 바로 합성할 수 있다.
- 지오코더(`/req/address`)는 CORS 헤더가 없다. 정적 호스팅에는 프록시를 둘 수 없으므로
  JSONP(`callback=`)로 부른다 — `lib/services/jsonp/`.
- 타일 경로는 `/req/wmts/1.0.0/{key}/{layer}/{z}/{y}/{x}.{ext}`로 **z/y/x 순서**이며
  좌표계는 표준 웹 메르카토르다.
