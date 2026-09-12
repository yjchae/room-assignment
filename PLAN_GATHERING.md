# 집회관리 시스템 기획서 (방배정 앞단 확장)

기존 방배정 앱(PLAN.md)은 **그대로 두고**, 그 앞에 "집회 설정 → 신청 접수 → 입금 확인" 단계를 붙인다.
입금이 확인된 신청자는 버튼 한 번으로 기존 참석자 목록에 들어가고, 거기서부터는 지금의 방배정 흐름과 똑같다.

```
[운영자] 집회 설정 ──공개 링크──▶ [신청자] 집회 페이지 → 신청서(본인+동반자) → 완료(금액·계좌 안내)
                                                                    │
[신청자] 신청 조회(휴대폰+PIN) ◀──────── 상태/입금 확인 ─────────────┤
                                                                    ▼
[운영자] 신청·입금 관리: 입금 확인 → 확정 ──[참석자로 가져오기]──▶ 기존 참석자 → 방배정 → 현황
```

---

## 0. 먼저 정해야 할 것 (기본값으로 진행, 다르면 알려주세요)

| # | 질문 | 기본값 (이대로 만듦) | 다른 선택지 |
|---|---|---|---|
| 1 | "그룹당 회비"의 뜻 | **신청 1건(가족)당 고정 금액을 더한다** (예: 가족당 1만원) | 가족 합계 상한(최대 N원) / 그룹 정액제(인원 무관) |
| 2 | 할인 두 개가 겹치면 | **둘 다 적용**(전체참석 할인 → 기간 할인 순서로 곱) | 큰 할인 하나만 |
| 3 | 기간 할인(얼리버드) 기준일 | **신청일** — 제출 순간 금액이 확정돼 안내가 쉽다 | 입금일 |
| 4 | 나이 구분 | **출생연도 입력 → 연 나이(올해−출생연도)** 로 구분. 학년과 정확히 맞는다 | 만 나이 / 구분 직접 선택 |
| 5 | 가족 방배정 | 자동배정에 **'가족' 묶음 기준**만 추가. 남녀 섞인 가족은 성별 분리를 끄고 돌리거나 수동 배정 | 가족이면 성별 분리 예외 처리(알고리즘 변경) |

---

## 1. 구조

### 1.1 왜 서버가 필요해졌나
지금은 **운영자 PC 한 대 + 로컬 JSON 파일**이다. 새 요구사항 중 두 가지가 이걸 넘는다.

- 신청자가 **자기 휴대폰에서** 신청서를 낸다.
- 신청자가 **나중에 다시 조회**한다.

→ 신청 데이터는 인터넷 어딘가에 있어야 한다. 직접 서버를 짜지 않고 **Supabase 무료 요금제**를 쓴다.

### 1.2 왜 Supabase 인가 (Firebase 대신)
관리자 앱은 **Windows 에서도 돌아야 한다.** Firebase 공식 문서는 Windows 를 "개발용으로만, 실서비스용 아님"으로 못박고 있다.
Supabase 클라이언트는 순수 Dart 라 macOS·Windows·웹에서 똑같이 돈다.

그 외 이 프로젝트에 맞는 점:
- 이미지 저장소가 무료 요금제에 포함
- DB 함수(RPC)로 **휴대폰+PIN 조회를 서버 쪽에서 안전하게** 검사할 수 있다 (틀린 횟수 제한 포함)
- 대시보드에서 신청 데이터를 **엑셀처럼 보고 CSV 로 내보내기** 가능

### 1.3 무료 한도 (Supabase 요금 페이지 기준, 2026-09)

| 항목 | 한도 | 이 프로젝트 예상 |
|---|---|---|
| DB | 500MB | 신청 1건 ≈ 2KB → 수십만 건 |
| 파일 저장 | 1GB | 집회당 이미지 2장 ≈ 0.3MB (§2.3에서 줄임) |
| 전송량 | 5GB + CDN 캐시 전송 5GB / 월 | 페이지 1회 열람 ≈ 0.3MB → 월 1만 회 열람도 여유 |
| 업로드 1개 | 50MB | 앱에서 줄여서 올리므로 해당 없음 |
| 이미지 자동 변환 | 없음 | 그래서 **앱이 올리기 전에 직접 줄인다** |
| 자동 백업 | 없음 | 대시보드 CSV 내보내기로 집회마다 수동 백업 |
| **일시정지** | **1주일간 DB 사용이 없으면 멈춤** | §1.5 로 방지. 멈춰도 데이터는 그대로, 1년 안에 [Resume] |

### 1.4 앱 구성

| | 누가 | 어디서 | 데이터 |
|---|---|---|---|
| **관리자 앱** (지금 앱) | 운영자 | **macOS / Windows** | 집회·신청·이미지 = Supabase / **방·참석자·배정 = 지금처럼 로컬 JSON** |
| **신청 웹** (새 진입점 `lib/main_public.dart`) | 신청자 | 휴대폰 브라우저 (카톡 링크) | Supabase |

- 같은 Flutter 프로젝트에서 웹으로 빌드한다. **회비 계산 코드를 신청 웹과 관리자 앱이 같이 쓰기 위해서**다 (따로 짜면 금액이 어긋난다).
- 신청 웹은 **GitHub Pages**(무료, 월 100GB)에 올린다. 무료 계정은 공개 저장소만 Pages 를 쓸 수 있으므로 **저장소를 공개로 바꾼다.**
  배포 = `main` 에 push 하면 `.github/workflows/deploy-web.yml` 이 `flutter build web -t lib/main_public.dart --base-href /room-assignment/` 로 빌드해 올린다.
  링크: `https://yjchae.github.io/room-assignment/?g=<집회id>`
- 방배정 데이터는 로컬에 그대로 둔다 → **수련회 장소에 인터넷이 안 돼도 방배정은 계속 된다.** 서버는 집회설정/신청·입금 탭에서만 필요하다.

> `ponytail:` 방배정 데이터까지 서버로 옮기면 여러 PC 동시 작업이 되지만 요구사항에 없다. 필요해지면 `Store.save()` 가 파일 대신 DB 행 하나에 JSON 을 쓰도록 바꾸면 된다.

### 1.5 일시정지 방지
1. **자동 깨우기**: `.github/workflows/keepalive.yml` — GitHub Actions 가 3일마다 `gatherings` 를 1행 조회한다.
   공개 저장소는 Actions 가 무료 무제한이다. 단, **60일간 커밋이 없으면 GitHub 가 예약 실행을 끈다** (끄기 전에 메일이 오고, Actions 탭에서 [Enable workflow] 한 번이면 다시 켜진다).
   → 집회 사이에 몇 달 쉬면 꺼질 수 있으니 아래 2번을 같이 한다.
2. **운영 체크리스트**: 신청 공지 올리기 전에 신청 링크를 한 번 열어본다. 안 열리면 Supabase 대시보드에서 [Resume project], GitHub Actions 탭에서 keepalive 가 꺼져 있으면 [Enable workflow].

### 1.6 키 관리
- 앱에 넣는 건 **공개용(anon/publishable) 키**뿐이다. 이 키는 원래 공개돼도 되는 키고, 실제 권한은 §6 의 보안 규칙(RLS)이 막는다.
- **service_role 키는 앱·저장소 어디에도 넣지 않는다** (모든 규칙을 무시하는 키).
- 저장소가 공개이므로 **커밋 금지**: service_role 키, DB 비밀번호, 실제 참석자 데이터(`event.json` 은 앱 데이터 폴더에 저장돼 저장소 밖이라 지금도 안전), 실명·실제 전화번호가 든 테스트 데이터.

---

## 2. 집회 설정 (운영자)

### 2.1 설정 항목

| 구분 | 항목 | 예 |
|---|---|---|
| 기본 | 집회 이름 | 신촌하나교회 가족수양회 |
| | 주제 (여러 개, 칩으로 입력) | 영혼육, 다음세대 |
| | 일정 | 2026-10-09(금) ~ 10-11(일) → 2박3일 (기존 Event 시작/종료일과 같은 값) |
| | 장소명 / 주소 | ○○수양관 / 경기도 가평군 … (신청 웹에서 [지도 보기] = 네이버지도 검색 링크) |
| | 안내 문구 (여러 줄) | 준비물, 문의처 등 |
| 이미지 | 포스터 (세로) | 신청 웹 상단에 크게 |
| | 배경 (가로) | 신청 웹 배경(어둡게+흐리게 깔고 글씨는 위에) + 관리자 집회 목록 카드 |
| 회비 | 연령 구분별 금액표 (§3) | |
| | 그룹(신청 1건)당 금액 | 10,000 |
| | 전체 참석 할인율 | 0% |
| | 기간 할인 (여러 구간) | 09-01~09-20 신청 시 10% |
| 입금 | 은행 / 계좌번호 / 예금주 | 국민 000-00-0000 / 신촌하나교회 |
| 신청 | 신청 받기 켜기/끄기, 마감일(선택) | |
| | 추가 입력 항목 | 기존 "사용자 정의 항목"(교회, 직분 …) 그대로 신청서에 나온다 |

- 저장하면 로컬 `Event` 의 이름/시작일/종료일/사용자 정의 항목도 같이 갱신 → **방배정 쪽 코드는 아무것도 몰라도 된다.**
- [신청 링크 복사] 버튼 (카톡 공지용).

### 2.2 집회 목록 (새 첫 화면)

지금은 앱 = 집회 1개. 앞으로는 잠금 해제 후 **집회 목록**(배경 이미지 카드, 일정, 신청 n건 · 확정 m건) → 하나 고르면 지금의 탭 화면으로 들어간다.

탭: **집회 설정 · 신청·입금** · 방 관리 · 참석자 · 방배정 · 자동배정 · 현황 (앞의 2개가 새것, 뒤 5개는 기존 그대로)

- 로컬 파일은 집회별로 `events/<집회id>.json`. 기존 `event.json` 은 첫 실행 때 첫 번째 집회로 옮긴다.
- 서버에 연결이 안 되면 목록은 이 PC 에 파일이 있는 집회만 보여준다 (방배정은 계속 가능).

### 2.3 이미지 — 올리기 전에 앱이 줄인다

운영자는 휴대폰 사진이든 디자이너 원본이든 **아무 크기나 고르면 된다.** 관리자 앱이 줄여서 올린다.
(Supabase 무료 요금제엔 이미지 자동 변환이 없고, 원본 5MB 를 그대로 올리면 페이지 열 때마다 5MB 씩 나간다.)

| | 최대 가로폭 | JPEG 품질 | 목표 크기 | 이유 |
|---|---|---|---|---|
| 포스터 | 900px | 80 | ≤ 250KB | 휴대폰 화면 폭(≈400pt) × 2배 해상도면 충분 |
| 배경 | 960px | 60 | ≤ 80KB | 어둡게+흐리게 깔리므로 저해상도로도 티가 안 난다 |

- 목표 크기를 넘으면 품질을 10씩 낮춰 다시 (최저 50).
- 올리기 전 미리보기 + **"4.2MB → 230KB"** 표시.
- 받는 형식: JPG / PNG / WebP (원본 20MB 이하). 아이폰 HEIC 는 못 읽으므로 "JPG 로 저장해서 올려주세요" 안내.
- 줄이는 작업은 `image` 패키지(순수 Dart → Windows 도 됨)로 **별도 isolate** 에서 — 큰 사진은 1~2초 걸려서 화면이 멈추지 않게.
- 저장: 공개 버킷 `gathering-images/<집회id>/poster-<시각>.jpg`, 캐시 1년.
  파일명에 시각을 넣어 **교체할 때마다 새 이름** → 브라우저·CDN 이 옛 이미지를 붙들고 있을 일이 없고, 다시 방문한 사람은 캐시에서 읽어 전송량이 안 든다. 교체하면 옛 파일은 지운다.

---

## 3. 회비 계산

### 3.1 연령 구분

출생연도로 연 나이(`집회 연도 − 출생연도`)를 구해 구분한다. 경계는 운영자가 바꿀 수 있다.

| 구분 | 연 나이 (기본) | 학년 |
|---|---|---|
| 영유아 | 0 ~ 3 | |
| 유치 | 4 ~ 6 | |
| 초등 | 7 ~ 12 | 초1 ~ 초6 |
| 중고등 | 13 ~ 18 | 중1 ~ 고3 |
| 성인 | 19 ~ | |

### 3.2 금액표 (구분 × 참석 형태)

| 구분 | 전체 참석 (정액) | 부분 참석 1박당 | 당일(무박) |
|---|---|---|---|
| 성인 | 150,000 | 70,000 | 30,000 |
| 중고등 | 120,000 | 60,000 | 25,000 |
| 초등 | 100,000 | 50,000 | 20,000 |
| 유치 | 60,000 | 30,000 | 10,000 |
| 영유아 | 0 | 0 | 0 |

### 3.3 계산 규칙

```
1인 금액
  전체 참석 = 전체정액[구분]  (비워두면 1박당 × 전체 박수)  × (1 − 전체참석 할인율)
  부분 참석 = 박수 > 0 ? 1박당[구분] × 박수 : 당일[구분]
              단, 전체 참석 금액을 넘지 않는다   (2박 부분참석이 전체참석보다 비싸지는 일 방지)

신청 합계 = Σ 1인 금액 × (1 − 기간할인율[신청일])  +  그룹당 금액
            원 미만 버림
```

예) 2박3일, 9/10 신청(얼리버드 10%), 그룹당 10,000원

| 이름 | 구분 | 일정 | 금액 |
|---|---|---|---|
| 아빠 | 성인 | 전체 | 150,000 |
| 엄마 | 성인 | 전체 | 150,000 |
| 첫째(2012년생) | 중고등 | 전체 | 120,000 |
| 둘째(2021년생) | 유치 | 토~일 1박 | 30,000 |
| 소계 | | | 450,000 |
| 기간 할인 10% | | | −45,000 |
| 그룹당 | | | +10,000 |
| **합계** | | | **415,000** |

신청서 하단에 이 표가 **입력하는 대로 바로 바뀌며** 보인다. 조회 화면·관리자 화면도 같은 표를 쓴다.

- 계산 함수는 `lib/gathering.dart` 의 `quote()` 하나. 위 예시를 그대로 `test/fee_test.dart` 로 박아둔다.
- 신청 웹이 계산한 금액은 **참고용으로만 저장**(`quoted`)한다. 관리자 앱은 항상 다시 계산해서 보여주고, 다르면 표시한다 (브라우저 값은 조작될 수 있고, 회비 설정이 나중에 바뀔 수도 있다).
- 신청일(`created_at`)은 DB 가 `now()` 로 찍는다 → 브라우저 시계를 바꿔서 얼리버드를 받을 수 없다.

---

## 4. 신청 (신청 웹)

### 4.1 집회 페이지
배경 이미지 위에 포스터, 집회 이름, 주제 칩, 일정, 장소([지도 보기]), 안내 문구, 회비표, 입금계좌([복사]).
하단 버튼: **[신청하기] [신청 조회]**. 신청 마감이면 [신청하기] 대신 "마감되었습니다".

### 4.2 신청서 (한 페이지, 휴대폰 세로 기준)

**신청자(대표)**: 이름, 성별, 출생연도, 휴대폰, 셀/존, 사용자 정의 항목, 입금자명(기본=신청자 이름), 메모, **조회용 PIN 4자리**

**동반 참석자** [+ 추가] 반복: 이름, 성별, 출생연도, 관계(배우자/자녀/부모/기타), 셀/존(기본 = 신청자와 같음)

**사람마다 참석 일정**: [전체 참석] 기본 켜짐 → 끄면 도착일 · 출발일 선택(집회 기간 안에서만)

**하단 고정 바**: `성인 2 · 중고등 1 · 유치 1  |  합계 415,000원  [내역 ▾]`

**개인정보 수집·이용 동의** 체크 (필수 — 수집 항목, 목적: 집회 운영/방배정, 보유기간: 집회 종료 후 3개월).

[신청하기] → 확인 창(인원·일정·금액) → 제출 → **완료 화면**: 금액, 입금계좌([복사]), "입금자명을 ○○○(으)로 해주세요", "휴대폰번호와 PIN으로 조회할 수 있습니다".

검증: 이름·성별·출생연도 필수, 휴대폰 형식(010-…), PIN 숫자 4자리, 도착일 ≤ 출발일, 1~20명.
**휴대폰 1개 = 신청 1건.** 같은 번호로 이미 신청이 있으면 "이미 신청하셨습니다 — 조회에서 수정하세요" 안내 (가족은 한 신청서에 동반자로 넣는다).

### 4.3 신청 조회
휴대폰 + PIN → 내 신청:

- 상태 배지: **입금대기 / 입금확인(확정) / 취소**
- 참석자·일정·금액 내역, 확인된 입금액, 입금계좌
- **입금대기일 때만** [수정] [신청 취소] 가능. 확정 후에는 "변경은 담당자에게 문의" 안내.
- PIN 을 **30분 안에 5번 틀리면** 그 번호는 30분간 조회 잠금 (DB 함수 안에서 처리 — 4자리 PIN 을 전부 대입해 보는 걸 막는다).
- PIN 을 잊으면 → 운영자가 관리자 앱에서 새 PIN 을 정해준다.

---

## 5. 신청·입금 관리 (운영자, 관리자 앱)

### 5.1 목록
| 신청일 | 신청자 | 인원 | 일정 | 금액 | 입금자명 | 입금액 | 상태 |
|---|---|---|---|---|---|---|---|
| 09-10 | 홍길동 | 성인2·중고등1·유치1 | 전체3·부분1 | 415,000 | 홍길동 | — | 입금대기 |

- 필터: 상태(전체/입금대기/확정/취소), 검색(신청자·동반자 이름, 입금자명, 휴대폰)
- 상단 합계: 신청 n건 · m명 / 입금대기 합계 / 확정 합계
- 행 표시: **금액 불일치**(신청 때 금액 ≠ 지금 계산 금액), **차액**(입금액 ≠ 금액)

### 5.2 입금 확인
- 행 선택 → 오른쪽 상세(참석자, 금액 내역) → **[입금 확인]** 창: 입금액(기본 = 금액), 입금일(기본 = 오늘), 입금자명 → **확정**.
  입금액이 금액과 다르면 경고만 하고 확정은 된다 (현장에서 필요한 경우가 있음 — 초과배정을 막지 않는 기존 원칙과 같다).
- 여러 행 체크 → **[일괄 확정]** (입금액 = 금액).
- [취소] — 확정된 건 취소 시 메모(환불 등) 입력.
- 운영자는 확정 후에도 신청 내용을 고칠 수 있다. 금액이 늘면 차액이 표시된다.
- [PIN 재설정].

### 5.3 참석자로 가져오기 (방배정과 연결)
참석자 탭에 **[신청에서 가져오기]** 버튼 하나. 서버에서 **확정된 신청**을 읽어 로컬 참석자와 맞춘다:

| 신청 쪽 | 참석자 쪽 동작 |
|---|---|
| 새로 확정된 사람 | 추가 |
| 내용이 바뀐 사람 | 이름·성별·나이·전화·셀·존·사용자항목·일정만 덮어씀. **배정된 방(roomId)과 기타(note)는 유지** |
| 취소된 신청 | 제거. 방이 배정돼 있었으면 목록을 보여주고 확인 후 제거 |

결과: "추가 5 · 변경 2 · 제거 1" 스낵바. 몇 번 눌러도 같은 결과(사람마다 고정 id 로 맞춤).

변환: `Attendee.id = Person.id`, `age = 집회연도 − 출생연도`, `phone = 본인 번호 ?? 신청자 번호`, 전체 참석이면 체크인/아웃 = 집회 시작/종료일.
`Attendee` 에 `registrationId` 필드 1개 추가 → 자동배정 묶음 기준에 **'가족'** 한 줄 추가 (`GroupField.of` 에 case 하나).

붙여넣기 등록은 그대로 둔다 — 현장 등록자, 신청 없이 오는 강사/스태프용.

---

## 6. 데이터 (Supabase)

`supabase/schema.sql` 한 파일에 테이블 + 권한 + 함수를 전부 둔다. 회비표·참석자 목록은 **jsonb 한 칸**에 Dart 모델을 그대로 넣는다 (컬럼으로 쪼갤 이유가 없다 — 조건 검색은 신청 단위로만 한다).

```sql
create extension if not exists pgcrypto;

create table admins (user_id uuid primary key references auth.users on delete cascade);
create function is_admin() returns boolean language sql stable security definer as
  $$ select exists (select 1 from admins where user_id = auth.uid()) $$;

create table gatherings (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  themes text[] default '{}',
  place text, address text, notice text,
  start_date date not null, end_date date not null,
  poster_url text, background_url text,
  fee jsonb not null default '{}',        -- FeeRule
  bank jsonb,                              -- {bank, account, holder}
  form_fields text[] default '{}',         -- 사용자 정의 항목
  open boolean default false, deadline date,
  created_at timestamptz default now()
);

create table registrations (
  id uuid primary key default gen_random_uuid(),
  gathering_id uuid not null references gatherings on delete cascade,
  phone text not null,                     -- 숫자만
  pin_hash text not null,                  -- crypt(pin, gen_salt('bf'))
  people jsonb not null,                   -- [Person], [0] = 신청자
  depositor text, memo text,
  quoted int not null,                     -- 신청 때 보여준 금액(참고)
  status text not null default 'pending' check (status in ('pending','confirmed','cancelled')),
  paid int not null default 0, paid_at date, admin_memo text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- 부분 유니크 인덱스 (gathering_id, phone) where status <> 'cancelled'
--   → 진행 중인 신청은 1번호 1건, 취소한 사람은 다시 신청 가능

create table lookup_failures (phone text not null, at timestamptz not null default now());  -- PIN 오답 기록
```

권한 (RLS):

| 대상 | 누구나(신청자) | 운영자 (`is_admin()`) |
|---|---|---|
| `gatherings` | 읽기 | 읽기·쓰기 |
| `registrations`, `lookup_failures` | **직접 접근 불가** — 아래 함수로만 | 읽기·쓰기 |
| 스토리지 `gathering-images` | 읽기(공개 버킷) | 올리기·지우기 |

- 운영자 계정은 Supabase 대시보드에서 직접 만들고 `admins` 에 한 줄 넣는다. **공개 회원가입은 끈다.**
  (가입을 실수로 켜 둬도 `admins` 에 없으면 운영자가 아니다 — 이중 잠금)

신청 웹이 부르는 함수 (전부 `security definer`, 함수 안에서 검사):

| 함수 | 하는 일 |
|---|---|
| `submit_registration(gathering_id, phone, pin, people, depositor, memo, quoted)` | 신청 받는 중인지·마감일·인원 1~20명 확인 후 insert. 번호 중복이면 에러 |
| `lookup_registration(gathering_id, phone, pin)` | 최근 30분 오답 5회면 거부 → PIN 확인 → 신청 반환 (`pin_hash`·`admin_memo` 는 빼고). 틀리면 `lookup_failures` 에 기록하고 에러 대신 **null** (에러를 던지면 오답 기록까지 롤백돼 횟수 제한이 무력화된다) |
| `update_registration(gathering_id, phone, pin, people, depositor, memo, quoted)` | PIN 확인 + `pending` 일 때만 수정. 상태·입금액은 못 건드린다 |
| `cancel_registration(gathering_id, phone, pin)` | PIN 확인 + `pending` 일 때만 취소 |
| `reset_pin(registration_id, pin)` | 운영자 전용 |

- 실제 SQL 전체는 `supabase/schema.sql`. 권한 검증은 `supabase/test.sql` — 로컬 Postgres 에 Supabase 흉내(auth·storage·역할)를 깔고,
  로그인 안 한 상태로 신청 목록 읽기 / 확정으로 바꾸기 / 입금액 바꾸기 / 마감 후 신청 / PIN 6회째 등이 전부 거부되는지 본다.

Dart 모델 (`lib/gathering.dart`, 파일 하나):

```dart
enum AgeGroup { adult, youth, child, kinder, infant } // 성인 중고등 초등 유치 영유아

class FeeRule {
  Map<AgeGroup, int?> full;      // 전체 참석 정액 (null = 1박당 × 박수)
  Map<AgeGroup, int> perNight;   // 부분 참석 1박당
  Map<AgeGroup, int> dayOnly;    // 당일
  Map<AgeGroup, int> minAge;     // 구분 시작 연 나이 (성인 19, 중고등 13 …)
  int perRegistration;           // 그룹(신청 1건)당
  int fullDiscountPct;           // 전체 참석 할인 %
  List<({DateTime from, DateTime to, int pct})> periods; // 기간 할인
}

class Gathering { String id, name; List<String> themes; String? place, address, notice, posterUrl, backgroundUrl;
                  DateTime start, end; FeeRule fee; Bank? bank; List<String> formFields; bool open; DateTime? deadline; }

class Person { String id, name, gender, relation; int birthYear; DateTime? checkIn, checkOut; // null = 집회 시작/종료일
               String? phone, cell, zone; Map<String, String> extra; }

class Registration { String id, gatheringId, phone; List<Person> people; String? depositor, memo;
                     int quoted, paid; String status; DateTime createdAt; DateTime? paidAt; }

/// 신청 합계와 내역. 신청 웹·조회·관리자 화면 전부 이것 하나를 부른다. (구현됨: lib/gathering.dart)
/// 전체 참석 여부는 필드로 두지 않고 "일정 = 집회 기간 전체" 로 판정한다 (상태가 어긋날 일이 없게).
Quote quote(FeeRule fee, {required DateTime start, required DateTime end,
                          required List<Person> people, required DateTime appliedAt});
```

---

## 7. 파일 구조 (추가분)

```
lib/
  main.dart                     (수정) 잠금 → 집회 목록 → 탭 7개
  main_public.dart              (신규) 신청 웹 진입점: 집회 페이지 / 신청서 / 조회
  gathering.dart                (신규) Gathering·FeeRule·Person·Registration + quote()
  config.dart                   (신규) 서버 주소·공개용 키·신청 링크
  remote.dart                   (신규) Supabase 호출 모음 (목록·저장·RPC·이미지 줄이기+업로드)
  widgets/quote_table.dart      (신규) 금액 내역표·신청 상태 뱃지 (두 앱 공용)
  screens/gatherings.dart       (신규) 집회 목록
  screens/gathering_settings.dart (신규) 집회 설정
  screens/registrations.dart    (신규) 신청·입금 관리
  models.dart                   (수정) Attendee.registrationId
  store.dart                    (수정) 집회별 파일 경로 + applyGathering() + syncRegistrations()
  auto_assign.dart              (수정) GroupField '가족'
supabase/schema.sql             (신규) 테이블 + RLS + 함수 + 스토리지 버킷 권한
.github/workflows/keepalive.yml (신규) 3일마다 DB 1행 조회
.github/workflows/deploy-web.yml (신규) main push → 신청 웹 빌드 → GitHub Pages
test/fee_test.dart              (신규) 회비 계산 — §3.3 예시 + 경계(부분>전체 상한, 할인 겹침, 영유아 0원)
supabase/test.sql               (신규) 로컬 Postgres 에서 권한·함수 거부 시나리오 검증
test/gathering_test.dart        (신규) 모델 JSON · 이미지 줄이기 · 신청 → 참석자 가져오기 · '가족' 기준
test/gathering_widget_test.dart (신규) 신청 웹(휴대폰 폭)·관리자 화면 — 가짜 서버로
```

- `main_public.dart` 는 `dart:io` 를 쓰는 `store.dart`/`auth.dart` 를 import 하지 않는다 (웹 빌드가 깨짐).
- 새 의존성: `supabase_flutter`(서버·로그인·스토리지), `file_picker`(이미지 고르기), `image`(줄이기, 순수 Dart).
  macOS 는 entitlements 에 `com.apple.security.network.client` 와 사용자 선택 파일 읽기 권한 추가.
- 기존 로컬 비밀번호 잠금(auth.dart)은 그대로 둔다 — 오프라인에서도 앱은 열려야 한다. Supabase 로그인은 집회설정/신청·입금 탭에 처음 들어갈 때 한 번 (세션 저장).

---

## 8. 구현 순서

1. **`gathering.dart` + `quote()` + `fee_test.dart`** — 돈 계산이 먼저 맞아야 나머지가 의미 있다
2. Supabase 프로젝트 생성 + `schema.sql` 적용, 운영자 계정 1개, 권한 거부 시나리오 확인, `keepalive.yml`
3. 집회 목록 + 집회 설정 화면 (이미지 줄이기+업로드, `image_test.dart`), Store 집회별 파일 + 기존 event.json 이전
4. 신청 웹: 집회 페이지 → 신청서 → 완료, 저장소 공개 전환 + GitHub Pages 자동 배포
5. 신청 조회 + 수정/취소
6. 신청·입금 관리 (확인·일괄 확정·취소·PIN 재설정)
7. 참석자로 가져오기 + 자동배정 '가족' 기준
8. 기존 테스트 전부 통과 + **Windows 에서 관리자 앱 한 바퀴** (로그인 → 이미지 업로드 → 입금 확인 → 가져오기 → 방배정)

---

## 9. 나중에 (지금 안 만드는 것)

- **은행 거래내역 붙여넣기 자동 대사** — 인터넷뱅킹 거래내역을 붙여넣으면 입금자명+금액으로 신청과 짝지어 일괄 확정. 기존 붙여넣기 파서 재사용. 신청이 수백 건 넘어가 수동 확인이 힘들어지면.
- 문자/알림톡 발송 (신청 완료·입금 확인) — 유료 서비스 연동 필요
- 온라인 결제(카드/간편결제) — PG 계약 필요
- 정원 제한·대기자 — 요청 오면 `gatherings.capacity` 한 칸
- 식사 인원 집계, 차량/셔틀 신청 — 사용자 정의 항목으로 먼저 받아보고 부족하면
- 방배정 데이터 서버 이전(여러 PC 동시 작업)
- 신청 링크 QR 코드
- HEIC(아이폰 원본) 이미지 읽기 — 운영자가 불편해하면
- 자동 백업 — Pro 요금제($25/월) 또는 GitHub Actions 로 주 1회 `pg_dump`
- 집회 종료 후 개인정보 일괄 삭제 버튼 (지금은 집회 삭제 = 신청 전체 삭제로 대체)
- 운영자가 관리자 앱에서 신청자 명단(사람) 고치기 — 지금은 신청자가 입금 전 [조회 → 수정]으로 고치거나,
  운영자가 [입금대기로 되돌리기] 후 신청자에게 수정을 부탁한다. 요청 오면 신청서 입력칸을 관리자 앱에서 재사용.

---

## 10. 구현 현황 (2026-09-13)

1~8단계 구현 완료. 기획과 달라진 점:

- **당일(0박) 참석자는 [신청에서 가져오기]에서 빠진다.** 방이 필요 없고, 방배정 쪽 정원 계산은
  "하룻밤도 안 겹치는 사람 = 모든 밤 차지"로 세기 때문에 넣으면 정원이 틀어진다. 가져오기 결과에 "당일 N명 제외"로 표시.
- 운영자의 신청자 명단 수정은 §9 로 미뤘다.
- 신청 조회는 휴대폰+PIN (서버 함수에서 30분 5회 잠금) — §0 결정대로.
- 이미지 줄이기: EXIF 회전 반영, 투명 PNG 는 흰 바탕, 깨진 파일은 "읽지 못했습니다" 안내.

운영자가 할 일 (코드 밖):

1. 저장소 공개 전환 → Settings → Pages → Source: **GitHub Actions**
2. `feature/gathering` 을 `main` 에 합치기 → deploy-web(신청 웹 배포)·keepalive 가 main 에서 돌기 시작
3. **Windows PC 에서 관리자 앱 한 바퀴** (로그인 → 이미지 업로드 → 입금 확인 → 가져오기 → 방배정) — macOS 에서는
   Windows 빌드를 할 수 없어 아직 못 해봤다.
