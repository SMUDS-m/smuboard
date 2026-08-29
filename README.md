# SMUBoard — 재난현장 조사

세명대학교 재난안전학과 재난현장 조사 앱. 현장사진에 조사 보드와 브이월드 약도를
합성하고, 현황조사표를 HWPX로 만들어 구글 드라이브에 저장한다.

모바일 웹(Flutter Web)으로 동작하며 GitHub Pages에 배포한다.

## 흐름

```
구글 로그인 → 조사 목록 → 조사 개요 → 현장 촬영 → 현황조사표 → 검토·제출
```

촬영한 사진은 합성 직후 곧바로 드라이브에 올라간다. 모바일 웹은 탭이 백그라운드에서
정리되면 메모리의 사진이 사라지므로, 가장 잃기 쉬운 것을 가장 오래 들고 있지 않기
위해서다. 제출 단계에서는 나머지 세 산출물만 만든다.

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

두 가지를 등록해야 배포본이 동작한다. 값 자체는 저장소 Secret으로만 주입한다
(`Settings → Secrets and variables → Actions`).

| Secret | 발급처 | 함께 해야 할 등록 |
|---|---|---|
| `GOOGLE_WEB_CLIENT_ID` | Google Cloud 콘솔 → 사용자 인증 정보 → 웹 클라이언트 | 승인된 자바스크립트 원본에 `https://<계정>.github.io` 추가 |
| `VWORLD_KEY` | 브이월드 오픈API | 서비스 URL(도메인)에 같은 주소 등록 |

클라이언트 웹앱이라 두 값 모두 빌드 결과에 남는다. 실제 보호는 위 도메인 등록으로
한다 — Secret은 저장소 소스와 커밋 이력에 키를 남기지 않기 위한 것이다.

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
