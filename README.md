# 뚜래블 (DDuddu Travel) 🐾

내가 다녀온 여행지를 지도에 색칠하고, 펫 캐릭터를 키우는 여행 아카이브 웹앱.

- **배포**: Vercel (`vercel.json`이 모든 경로를 `/files/` 아래로 rewrite)
- **형태**: 빌드 도구 없는 **단일 HTML 파일** (`files/index.html`, 약 8.9MB)
- **백엔드**: Supabase REST API 직접 호출 (SDK 미사용)
- **모바일 우선** — 최대 폭 430px, iOS 홈 화면 추가(PWA 메타) 지원

---

## 1. 파일 구성

| 파일 | 크기 | 역할 |
|---|---|---|
| `files/index.html` | 8.9MB | **앱 전체** — HTML·CSS·JS·이미지·지도 데이터가 한 파일에 인라인 |
| `files/font.ttf` | 8.1MB | 커스텀 폰트 `Uiyeon` (동적 `@font-face` 주입) |
| `files/sigungu.json` | 1.5MB | 시군구 TopoJSON (※ 현재 앱은 이 파일을 읽지 않음 — 아래 참고) |
| `vercel.json` | — | `/` → `/files/index.html` rewrite |
| `files/dduddu_travel_v5_backup.html` | 8.9MB | 이전 버전 백업본 (미추적) |

### index.html 내부 구성 (약 3,940줄)

| 영역 | 위치 | 내용 |
|---|---|---|
| 폰트 로더 | 1~14 | `file://` / Vercel 경로를 구분해 `font.ttf` 경로 결정 |
| CSS | 25~274 | 핑크 파스텔 테마, CSS 변수(`--pk`, `--tx` …), 픽셀 감성 그림자 |
| 배경 이미지 | 275 | `BG_ROOM_B64` — 펫 방 배경 (base64 5.6MB) |
| 화면 마크업 | 283~635 | 온보딩 + 5개 페이지 + 모달 6종 |
| 외부 라이브러리 | 636~640 | d3 v7, topojson-client v3, pako v2.1, exifr v7 (CDN) |
| 지도 데이터 | 641~945 | 세계지도 SVG path(대륙별), 펫 스프라이트, `KR_B64` |
| 앱 로직 | 946~3940 | 상수·Supabase·온보딩·지도·여행·미션·친구·펫·사진 |

**인라인 에셋이 전체의 70%** — base64 이미지 6.25MB + 한국지도 0.67MB.

---

## 2. 화면 구성

온보딩(로그인) → 하단 탭 5개 구조.

| 탭 | 페이지 id | 기능 |
|---|---|---|
| 🏠 홈 | `pg-home` | 통계 4종(총 여행·여행일·국내/해외 달성률), 펫 위젯, 펫 상호작용 3종 |
| 🗺 지도 | `pg-map` | 국내 시군구 지도 / 세계지도(대륙 5개 탭), 클릭해서 색칠 |
| 📖 여행 | `pg-trips` | 여행 목록, 필터(전체/일정완료/일정대기), 검색, 사진으로 바로 추가 |
| ⭐ 미션 | `pg-missions` | 국내 도별 달성률 + 광역시 클리어, 해외 대륙별 달성률 |
| 👥 친구 | `pg-friends` | 친구 코드 검색·추가, 친구 여행 보기, 담은 여행 |

### 모달

`tripModal`(여행 상세) · `addTripModal`(여행 기록) · `exifModal`(사진 분석) · `popBg`(알림 팝업) · `backupPopup`(백업/복원) · 날짜 선택 캘린더(연/월/일 3단계).

---

## 3. 핵심 기능

### 3-1. 지도 색칠

- **국내**: `KR_B64`(gzip+base64된 TopoJSON)를 pako로 압축 해제 → d3로 렌더. 161개 시군구.
  - 광역시 8곳(`METRO_CODES`)은 구 단위 없이 **시 전체가 한 덩어리**
  - 지도 클릭 → `toggleSigungu()` → 여행 기록 모달
  - 줌 인/아웃/리셋 지원
- **해외**: 대륙별 SVG `<path>`가 HTML에 직접 박혀 있음 (`wc-{ISO}` id)
  - 5개 대륙 탭: 아시아 / 유럽 / 아메리카 / 오세아니아 / 아프리카·중동
  - `ISO_KR`(국가 한글명), `ISO_CONTINENT`(대륙 매핑) 상수로 관리
- **방문 횟수별 농도**: 1회 연분홍 → 5회 이상 진분홍 (`getVisitColorKr/Wd`)

### 3-2. 여행 기록

한 여행 = `{id, title, start, end, loc, locs[], days{}, photos[]}`

- 여행지는 **여러 곳 추가 가능** (`locs` 배열, 지도 클릭 또는 검색)
- 날짜: 자체 구현 캘린더 (연도 → 월 → 시작일 → 종료일)
- **일정(days)**: Day별 장소 목록. 장소마다 `{time, name, cat, memo}`
- **자동 분류**: 텍스트를 붙여넣으면 시간(`10시`, `10:30`)과 카테고리를 추론
  - 카테고리 6종: `food`(밥/카페) `sight`(관광명소) `shop`(쇼핑) `move`(이동) `activity`(액티비티) `stay`(숙소)
- 사진 첨부: 여행당 최대 5장, 1200px/JPEG 75%로 압축 후 base64 저장

### 3-3. 사진으로 자동 기록 (EXIF)

사진 여러 장 선택 → exifr로 촬영일시·GPS 추출 → Nominatim 역지오코딩 → 지역 자동 매칭 → 날짜 범위·대표 여행지가 채워진 여행 생성.

- exifr 실패 시 JPEG 바이너리를 직접 파싱하는 fallback 내장 (iOS Safari 대응)
- GPS는 최대 5장까지만 조회 (rate limit 고려, 300ms 간격)

### 3-4. 펫 육성

- 캐릭터 3종 선택: 골든 리트리버 / 시바견 / 줄무늬 고양이
- **레벨 = 방문지 수 기반**: 국내 전부 = Lv50, 해외까지 = Lv100
  - `recalcLevelFromTrips()`가 `visitedCodes`·`visitedISO` 개수로 매번 재계산
- **상호작용 3종**: 밥 🍚 / 공놀이 🎾 / 산책 🦮
  - 여행 1개당 각 1회, 미션 1개당 각 2회씩 충전
- 스프라이트 애니메이션: idle / walk / eat / play / sleep (4프레임), 방 안을 자유롭게 걸어다님

### 3-5. 미션

- 국내: 도별 방문 시군구 수 (경기 31곳, 강원 18곳 …) + "모든 광역시 클리어"
- 해외: 대륙별 방문 국가 수
- 달성 시 팝업 + 상호작용 횟수 지급, `completedMissions`에 기록

### 3-6. 친구

- 닉네임 기반 **6자리 내 코드** 자동 생성 (`genCode`)
- 코드로 친구 검색 → 추가 → 친구의 여행 목록 열람 → **내 여행으로 담기**

### 3-7. 백업 / 복원

- 상태 전체를 JSON으로 내보내기 / 붙여넣어 복원
- 구버전 localStorage 데이터 복구 기능 (`recoverFromLocalStorage`)
- 진단 화면(`showDiagnostics`)

---

## 4. 데이터

### 4-1. Supabase

- 프로젝트: `https://ptcuejfmsopyafngreea.supabase.co`
- 테이블 **`baljauk_users`** 하나만 사용
- anon 키를 HTML에 직접 넣고 `fetch`로 REST 호출 (`SUPA_HEADERS`)

| 컬럼 | 내용 |
|---|---|
| `name` | 닉네임 = **기본 키 역할** (`on_conflict=name`으로 upsert) |
| `password` | 비밀번호 (평문) |
| `my_code` | 친구 코드 |
| `data` | 유저 상태 전체가 담긴 JSON |
| `updated_at` | 저장 시각 |

DB 함수 4개: `dbGet(name)` / `dbGetByCode(code)` / `dbUpsert(row)` / `dbInsert(row)`

### 4-2. 상태 객체 `S`

```js
{
  name, pet, myCode,          // 프로필
  trips: [],                  // 여행 목록 (사진 base64 포함)
  visitedCodes: [],           // 방문한 국내 시군구 코드
  visitedISO: [],             // 방문한 해외 국가 ISO
  visitCounts: {},            // 지역별 방문 횟수 (색 농도용)
  completedMissions: [],
  petLevel, petLove, petXP,
  mealCharges, playCharges, walkCharges,
  friends: [], savedTrips: []
}
```

- **모든 변경은 `save()` 하나로 처리** — `S` 전체를 통째로 upsert
- `rebuildVisitData()`가 `trips`로부터 방문 데이터를 항상 재계산 (정합성 보정)

### 4-3. localStorage

`baljauk_autologin` — 자동 로그인용 `{name, pwd}`. 그 외 앱 데이터는 저장하지 않음.

---

## 5. 인증 흐름

닉네임 + 비밀번호 방식 (Supabase Auth 미사용).

1. 닉네임 입력 시마다 `dbGet()`으로 기존 계정 여부 조회
2. 있으면 → 비밀번호 비교 후 `S = row.data`
3. 없으면 → 캐릭터 선택 후 `dbInsert()`로 신규 생성
4. 자동 로그인 체크 시 `localStorage`에 닉네임·비밀번호 저장

---

## 6. 외부 의존성

| 라이브러리 | 용도 |
|---|---|
| d3 v7 | 국내 지도 렌더링·줌 |
| topojson-client v3 | TopoJSON → GeoJSON 변환 |
| pako v2.1 | `KR_B64` gzip 압축 해제 |
| exifr v7 | 사진 EXIF(촬영일시·GPS) 추출 |
| Nominatim (OSM) | 좌표 → 지역명 역지오코딩 |

전부 CDN(jsdelivr/unpkg) 직접 로드 — 번들러·패키지 매니저 없음.

---

## 7. 알아둘 점

- **`files/sigungu.json`은 현재 사용되지 않음.** 국내 지도는 HTML에 인라인된 `KR_B64`를 쓴다. 과거 흔적으로 남아 있는 파일.
- `CHAR_LIST`에는 캐릭터가 5종(캘리코·샴 고양이 포함) 정의돼 있지만, **애니메이션 스프라이트는 3종만** 존재해 선택 화면에도 3종만 노출된다.
- XP/레벨 관련 상수 일부(`XP_PER_LEVEL`, `TRIP_XP`, `MAX_LEVEL`)는 레벨 로직이 "방문지 수 기반"으로 바뀌면서 **사용되지 않는 잔재**다.
- 로컬에서 열 때(`file://`)와 배포 환경에서 폰트 경로가 달라지므로, 경로 로직을 건드릴 땐 양쪽 다 확인이 필요하다.

---

## 8. 로컬에서 실행

정적 파일이라 서버만 있으면 된다.

```bash
python3 -m http.server 5599
```

띄운 뒤 `http://localhost:5599/files/index.html` 접속.
