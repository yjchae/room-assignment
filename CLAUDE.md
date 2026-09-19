# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

집회(수련회) 운영 도구. Flutter 한 프로젝트에서 **진입점 두 개**를 빌드한다. 코드 주석·화면 문구는 모두 한국어로 쓴다.

| 진입점 | 누가 | 대상 | 배포 주소 |
|---|---|---|---|
| `lib/main.dart` | 운영자 | macOS / Windows / 웹 | `https://yjchae.github.io/room-assignment/admin/` |
| `lib/main_public.dart` | 신청자 | 휴대폰 브라우저 | `https://yjchae.github.io/room-assignment/?g=<집회id>` |

## 명령어

```sh
flutter pub get
flutter analyze && flutter test          # UI 고친 뒤 항상 (room-ui 스킬 §7)
flutter test test/auto_assign_test.dart  # 파일 하나
flutter test --plain-name '자동배정'      # 이름으로 group/test 하나
flutter run -d macos                                  # 운영자 앱
flutter run -d chrome -t lib/main_public.dart         # 신청 웹 (주소 뒤에 ?g=<집회id> 를 붙여야 뜬다)
psql -v ON_ERROR_STOP=1 -q -d <빈 DB> -f supabase/test.sql   # DB 스키마 검증, 끝까지 가면 "ALL OK"
```

- CI(`.github/workflows/deploy-web.yml`)는 Flutter **3.47.2** stable 이고, `main` 에 push 하면 `flutter test` → 두 웹 빌드 → GitHub Pages 배포 순서로 돈다. 테스트가 깨지면 배포하지 않는다.
- `supabase/schema.sql` 은 대시보드 SQL Editor 에 통째로 붙여 넣어 적용한다. 여러 번 돌려도 된다(테이블은 `if not exists`, 함수·정책은 덮어쓴다). 칸을 추가할 때는 `alter table ... add column if not exists` 줄도 같이 넣는다.

## 구조

**서버는 Supabase 하나다.** 테이블은 `gatherings`(집회 설정), `registrations`(신청), `room_plans`(방배정), `admins`.
- 방배정은 집회마다 `room_plans` 행 하나에 `Event` JSON 문서 전체를 저장한다(`lib/store.dart`). 요구사항·설계 이유는 `PLAN.md`(방배정)·`PLAN_GATHERING.md`(집회관리)에 있고, 처음 기획(로컬 JSON·로컬 잠금)에서 달라진 점은 `PLAN_GATHERING.md` §10 에 모아 두었다.
- 권한은 RLS 가 막는다. 신청자는 `registrations` 테이블에 직접 닿지 못하고 `submit_/lookup_/update_/cancel_registration` RPC(휴대폰+PIN)로만 드나든다.
- **운영자는 두 종류다.** 전체 운영자 = `admins` 에 있는 사람(모든 집회 + 계정 승인 + 새 집회 만들기·삭제). 집회별 운영자 = `gathering_admins` 에 그 집회로 등록된 사람(그 집회의 설정·신청·방배정만). 판정은 SQL 함수 `manages(집회id)` 하나로 한다 — RLS 정책도 운영자 RPC(`save_room_plan`·`admin_add_registration`·`reset_pin`)도 이걸 부른다. 등록은 집회 설정 화면의 [이 집회의 운영자] 카드에서 이메일로 한다(`add_gathering_admin`, 계정이 없으면 `NO_ACCOUNT`). 앱은 `remote.scope()` 로 범위를 읽어 집회 목록과 [새 집회]·[집회 삭제]를 가린다.
- `lib/config.dart` 에는 publishable 키만 둔다. 저장소가 공개라서 service_role 키, 실명·실제 전화번호가 든 데이터는 커밋하지 않는다.

**웹 빌드에 같이 들어가는 파일** — `gathering.dart`, `remote.dart`, `theme.dart`, `widgets/quote_table.dart`, `main_public.dart` 는 `dart:io` 를 import 하면 안 된다. `main_public.dart` 는 이 파일들만 가져온다.

**회비 계산은 `gathering.dart` 의 `quote()` 하나뿐이다.** 신청 웹·조회·관리자 화면·참석자 가져오기가 모두 이 함수를 부른다. 따로 계산하면 금액이 어긋난다.

**전역 상태** (`lib/main.dart`): `store`(방배정 `Store`, ChangeNotifier), `current`(열어 둔 `Gathering`), `tabIndex`. 탭 번호는 숫자 대신 `settingsTab`/`registrationsTab`/`assignTab` 상수로 쓴다. 서버 호출은 전부 `lib/remote.dart` 의 전역 `remote` 로 하고, 테스트는 여기에 `Remote` 를 상속한 가짜(`FakeRemote`, `PlanRemote`)를 끼운다.

**방배정 저장 흐름** (`Store`)
- 방배정을 바꾸는 코드는 `event` 를 고친 다음 반드시 `store.commit()` 을 부른다. commit 이 알림을 보내고 문서 전체를 저장한다. 저장은 한 번에 하나만 돌고, 저장 중에 또 바뀌면 끝난 뒤 최신 상태로 한 번 더 올린다.
- 동시 편집은 버전으로 막는다. `save_room_plan(p_version)` 이 `CONFLICT` 를 던지면 덮어쓰지 않고 서버 문서를 다시 읽는다.
- `gatheringId == null` 이면 저장하지 않는다(테스트가 이 상태로 돈다). `loadError` 가 있을 때도 저장하지 않는다. 빈 화면으로 서버 내용을 덮어쓰지 않기 위해서다.
- `applyGathering()` 은 집회 설정(이름·날짜·사용자 항목)을 `Event` 에 반영한다. 방배정 쪽 코드는 `Gathering` 을 몰라도 된다.

**집회 구분** (`Gathering.kind`): `집회` / `홈스테이`. 만들 때만 정한다.
- 홈스테이는 신청자가 재워 줄 **가정**이다. 확정하면 `Store.syncHomestayRooms` 가 그 이름으로 방을 만들고(`Room.registrationId` 로 신청과 묶는다), 운영자가 따로 등록한 참석자를 그 방에 배치한다. 신청자를 참석자로 가져오지 않는다.
- 방 정원은 신청서의 사용자 정의 항목 `수용 인원`(`homestayCapacityField`)에서 만들 때 한 번만 가져온다. 그 뒤엔 운영자가 고친 값이 이긴다.
- 신청자는 `lookup_registration` 이 같이 돌려주는 `assigned`(`schema.sql` 의 `_assigned`)로 자기 집에 배정된 사람을 본다. 운영자 메모는 빼고 준다.
- 화면은 같은 걸 쓰고 이름만 바꾼다(`방 관리 → 가정 관리`). 홈스테이의 [신청에서 가져오기]는 참석자 화면이 아니라 **가정 관리** 화면에 있다.

**기간을 나눈 참석자** (`Attendee.splitOf`): 한 사람이 기간별로 다른 방(홈스테이는 다른 집)에 묵으면 참석자 행이 조각으로 나뉜다. `Store.splitStay`(경계 날짜로 자르기)·`assignRange`(고른 기간만 배정, 나머지는 미배정 조각)가 만들고, 같은 사람은 `Attendee.personId` 로 묶어 화면에서 한 줄로 그린다. 조각도 제 일정을 가진 보통 참석자라 정원·보드·자동배정은 손댈 필요가 없다. 나뉜 조각은 `registrationId` 를 떼고 원본에 `editedByAdmin` 을 붙여 [신청에서 가져오기]가 되돌리지 않게 한다.

**일정표** (`Gathering.schedule`): `{date, time, title}` 목록을 `gatherings.schedule` 에 담는다. 집회 설정에서 날짜별로 적고, 신청 웹 집회 페이지에 보인다. 기간 밖 날짜의 항목은 화면에 안 보이지만 지우지도 않는다.

**신청 → 참석자** (`Store.syncRegistrations`): 확정된 신청의 사람을 사람 id 로 맞추기 때문에 몇 번을 불러도 결과가 같다. 1박 이상 묵는 사람만 가져오고, 가져올 때 `roomId`·`note` 는 건드리지 않는다. `Attendee.registrationId` 가 null 이면 붙여넣기나 직접 추가로 들어온 사람이라 동기화 대상에서 빠진다. 운영자가 고친 사람은 `editedByAdmin` 으로, 지운 사람은 `Event.deletedIds` 로 기억해 두었다가 `syncConflicts()` 로 어느 쪽 내용을 쓸지 묻는다.

**서버 에러 코드**: SQL 함수가 `CLOSED`, `INVALID_*`, `CONFLICT` 같은 문자열을 던지면(`schema.sql` 맨 위 목록) `remote.dart` 의 `errorText()` 가 안내 문구로 바꾼다. 코드를 새로 만들면 두 곳에 같이 넣는다.

**정원·방 보드**
- 방 인원은 항상 `store.peakOccupancy(room)` 으로 센다. 부분 참석자가 있어서 날짜가 겹치는 밤 중 가장 붐비는 밤을 기준으로 한다. `occupantsOf().length` 로 세면 틀린다.
- 방 상태는 `theme.dart` 의 `statusOf()` 하나로 판정한다.
- 방은 방 관리·방배정·현황 화면 모두 `widgets/room_board.dart` 의 `RoomBoard` 로 그린다. 층마다 `boardColumns`(10)칸 격자이고, 칸 수는 창 폭에 맞춰 줄이지 않는다. `Room.slot` 이 이 폭을 기준으로 저장돼 있기 때문이다. 자리 계산은 `models.dart` 의 `layoutSlots()` 가 맡는다.

**자동배정** (`lib/auto_assign.dart`): 그리디 3단계다(우대 대상 → 그룹을 큰 것부터 → 나머지). 설계 이유는 `PLAN.md` §3.4 에 있다. 미배정 인원만 채우고, 결과는 미리보기를 거친 뒤 적용한다.

## 규칙

- UI 를 만들거나 고칠 때는 `.claude/skills/room-ui/SKILL.md`(room-ui 스킬)를 따른다. 색은 `AppColors` 에서만 가져오고, 폰트는 Pretendard 400~700 만 쓴다(w800 이상 금지). `Material` 에 `shape` 와 `borderRadius` 를 같이 주면 런타임 assert 가 난다.
- 일부러 줄인 설계에는 `ponytail:` 주석으로 한계와 나중에 올릴 방법을 적는다(이미 쓰고 있는 관례). 상태관리·DI·라우터 패키지는 쓰지 않는다. 새 의존성을 넣기 전에 `pubspec.yaml` 에 이미 있는지 먼저 본다.
