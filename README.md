# 집회관리 · 방배정 (room-assignment)

수련회·집회를 운영하는 도구입니다. 신청 접수부터 회비·입금 확인, 방(홈스테이 가정) 배정, 스탭 담당구역까지 한곳에서 다룹니다.
Flutter 한 프로젝트에서 **운영자 앱**과 **신청 웹** 두 가지를 빌드하고, 서버는 Supabase 하나를 씁니다.

| | 누가 | 어디서 | 주소 |
|---|---|---|---|
| 운영자 앱 (`lib/main.dart`) | 운영자 | macOS · Windows · 웹(휴대폰·태블릿 포함) | https://yjchae.github.io/room-assignment/admin/ |
| 신청 웹 (`lib/main_public.dart`) | 신청자 · 스탭 | 휴대폰 브라우저 | `https://yjchae.github.io/room-assignment/?g=<집회id>` |

## 주요 기능

**신청자 (신청 웹)**
- 집회 페이지: 안내·일정표·회비표 보기
- 신청하기: 동반자 포함, 참석 날짜·숙박을 직접 골라 회비 자동 계산
- 휴대폰 번호 + PIN 으로 신청 조회 · 수정 · 취소
- 홈스테이 가정은 자기 집에 배정된 사람 확인
- 스탭 페이지(`?g=<집회id>&staff=1`): 맡은 담당구역의 할 일 적기

**운영자 (운영자 앱)**
- 집회 만들기·설정: 기간, 회비 규칙(연령별·당일 무료 날·숙박비 별도), 신청서 항목(기본 항목 받음/선택/필수, 추가 항목 텍스트·숫자·체크박스·셀렉트·토글), 일정표, 이미지
- 신청·입금: 신청 목록, 입금 확인, 은행 입출금 내역(xlsx) 대조, 운영자 대리 신청
- 방 관리 · 참석자 · 방배정(드래그) · 자동배정(미리보기 후 적용) · 현황
- 기간을 나눠 다른 방에 묵는 참석자, 홈스테이(가정 단위 배정)
- 담당구역 · 구역 할일
- 운영자 4단계 권한: 수퍼어드민 · 집회관리자 · 보조운영자 · 운영스탭(초대 링크로 가입 → 승인)
- 동시 편집 충돌 방지(버전 검사), 백업

사용법은 매뉴얼에 화면과 함께 있습니다.
- [운영자 매뉴얼](docs/manual/운영자_매뉴얼.md) ([PDF](docs/manual/운영자_매뉴얼.pdf))
- [사용자 매뉴얼](docs/manual/사용자_매뉴얼.md) ([PDF](docs/manual/사용자_매뉴얼.pdf))

## 구조

```
lib/
  main.dart            운영자 앱 진입점 (전역 상태: store · current · tabIndex)
  main_public.dart     신청 웹 진입점 (신청·조회·스탭 페이지)
  gathering.dart       집회 설정 모델, 회비 계산 quote()
  models.dart          방배정 문서(Event·Room·Attendee·Duty…)
  store.dart           방배정 저장 흐름(commit·버전 충돌·신청 동기화)
  remote.dart          Supabase 호출 전부 (전역 remote)
  auto_assign.dart     자동배정 (그리디 3단계)
  bank_import.dart     은행 입출금 xlsx 읽기·입금 대조
  responsive.dart      화면 크기 판정
  theme.dart           색·글꼴·방 상태
  screens/  widgets/   화면과 공용 위젯
supabase/
  schema.sql           DB 스키마·RLS·RPC (room 스키마, 여러 번 돌려도 됨)
  test.sql             스키마 검증 (빈 DB 에서 "ALL OK")
test/                  flutter test
tool/                  DB 백업, 앱 아이콘 생성, 매뉴얼 스크린샷
docs/manual/           운영자·사용자 매뉴얼
```

설계 문서: [PLAN.md](PLAN.md)(방배정) · [PLAN_GATHERING.md](PLAN_GATHERING.md)(집회관리) · [PLAN_RESPONSIVE.md](PLAN_RESPONSIVE.md)(반응형)

## 시작하기

필요: Flutter 3.47.2 (stable), Supabase 프로젝트

1. Supabase 대시보드 SQL Editor 에 `supabase/schema.sql` 을 통째로 붙여 넣어 실행합니다.
2. 대시보드 Settings → API → Exposed schemas 에 `room` 을 추가합니다.
3. `lib/config.dart` 에 프로젝트 URL 과 **publishable(anon) 키**를 넣습니다. service_role 키는 절대 넣지 않습니다.
   운영자 웹 주소(`adminSiteUrl`)는 Authentication → URL Configuration → Redirect URLs 에 등록합니다(비밀번호 재설정 메일).
4. 수퍼어드민은 가입으로 만들 수 없어 SQL 로 `room.admins` 에 넣습니다.

```sh
flutter pub get
flutter run -d macos                            # 운영자 앱
flutter run -d chrome -t lib/main_public.dart   # 신청 웹 (주소 뒤에 ?g=<집회id>)
flutter analyze && flutter test                 # 검사·테스트
```

## 배포

`main` 에 push 하면 GitHub Actions(`.github/workflows/deploy-web.yml`)가 `flutter test` → 운영자 웹·신청 웹 빌드 → GitHub Pages 배포를 합니다. 테스트가 실패하면 배포하지 않습니다.
`keepalive.yml` 은 무료 Supabase 프로젝트가 멈추지 않게 3일마다 한 번 읽습니다(저장소 Secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` 필요).

## 주의

저장소가 공개입니다. service_role 키, DB 비밀번호, 실명·실제 전화번호가 든 데이터(백업 `backups/`, 명단 xlsx/csv)는 커밋하지 않습니다. 매뉴얼 스크린샷의 이름은 모두 지어낸 것입니다.

## 사용한 오픈소스

이 프로젝트가 직접 쓰는 외부 오픈소스와 라이선스입니다. 각 패키지가 다시 끌어오는 하위 의존성은 `pubspec.lock` 에 있습니다.

**프레임워크 · 서비스**

| 이름 | 용도 | 라이선스 |
|---|---|---|
| [Flutter](https://github.com/flutter/flutter) (`flutter`, `flutter_localizations`, `flutter_test`) | 앱 프레임워크, 한국어 지역화 | BSD-3-Clause |
| [Supabase](https://github.com/supabase/supabase) | DB(PostgreSQL)·인증·스토리지 서버 | Apache-2.0 |

**Dart 패키지** (`pubspec.yaml`)

| 패키지 | 버전 | 용도 | 라이선스 |
|---|---|---|---|
| [supabase_flutter](https://pub.dev/packages/supabase_flutter) | 2.17.2 | Supabase 클라이언트(로그인·DB·RPC·스토리지) | MIT |
| [file_picker](https://pub.dev/packages/file_picker) | 12.3.0 | 이미지·입출금 내역 파일 열기, 백업 파일 저장·불러오기 | MIT |
| [image](https://pub.dev/packages/image) | 4.9.2 | 올리는 이미지 회전 보정·크기 줄이기 | MIT |
| [url_launcher](https://pub.dev/packages/url_launcher) | 6.3.2 | 신청 웹에서 링크·전화 열기 | BSD-3-Clause |
| [archive](https://pub.dev/packages/archive) | 4.2.0 | xlsx(zip) 풀기 | MIT |
| [xml](https://pub.dev/packages/xml) | 7.0.1 | xlsx 안의 시트 XML 읽기 | MIT |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | 1.0.9 | iOS 스타일 아이콘(Flutter 기본 템플릿) | MIT |
| [flutter_lints](https://pub.dev/packages/flutter_lints) (개발용) | 6.0.0 | 정적 분석 규칙 | BSD-3-Clause |

**글꼴**

| 이름 | 용도 | 라이선스 |
|---|---|---|
| [Pretendard](https://github.com/orioncactus/pretendard) © 2021 Kil Hyung-jin | 앱 전체 글꼴(400·500·600·700) | SIL OFL 1.1 — [assets/fonts/Pretendard-LICENSE.txt](assets/fonts/Pretendard-LICENSE.txt) |

**CI (GitHub Actions)**

| 액션 | 용도 | 라이선스 |
|---|---|---|
| [actions/checkout](https://github.com/actions/checkout) | 소스 받기 | MIT |
| [subosito/flutter-action](https://github.com/subosito/flutter-action) | Flutter 설치 | MIT |
| [actions/upload-pages-artifact](https://github.com/actions/upload-pages-artifact) · [actions/deploy-pages](https://github.com/actions/deploy-pages) | GitHub Pages 배포 | MIT |

개발 도구(앱에 들어가지 않음): `tool/backup_db.sh` 는 PostgreSQL `pg_dump`(PostgreSQL License), `tool/app_icon.py` 는 librsvg `rsvg-convert`(LGPL-2.1)를 씁니다.
