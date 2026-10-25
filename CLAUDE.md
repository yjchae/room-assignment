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

**서버는 Supabase 하나다.** 같은 프로젝트를 다른 앱(토라포션)도 `public` 에서 쓰므로 이 앱은 전부 **`room` 스키마**에 둔다(`Remote.init` 의 `PostgrestClientOptions(schema: 'room')`, 대시보드 Exposed schemas 에 `room`). `public` 으로 되돌리거나 거기 새로 만들지 않는다. 테이블은 `gatherings`(집회 설정), `registrations`(신청), `room_plans`(방배정), `admins`(수퍼어드민), `members`(이 앱 가입자), `gathering_admins`(집회별 보조운영자·운영스탭), `gathering_invites`(초대 링크 코드), `lookup_failures`(조회 PIN 실패 횟수). 옮긴 이력은 `supabase/move_to_room.sql`, 운영 DB 백업은 `sh tool/backup_db.sh`.
- 방배정은 집회마다 `room_plans` 행 하나에 `Event` JSON 문서 전체를 저장한다(`lib/store.dart`). 요구사항·설계 이유는 `PLAN.md`(방배정)·`PLAN_GATHERING.md`(집회관리)에 있고, 처음 기획(로컬 JSON·로컬 잠금)에서 달라진 점은 `PLAN_GATHERING.md` §10 에 모아 두었다.
- 권한은 RLS 가 막는다. 신청자는 `registrations` 테이블에 직접 닿지 못하고 `submit_/lookup_/update_/cancel_registration` RPC(휴대폰+PIN)로만 드나든다.
- **로그인 계정(`auth.users`)은 다른 앱과 같이 쓴다.** 이 앱 사람인지는 `room.members` 로 가리고, 로그인마다 `enter_app()`(앱 `remote.enter`)이 판정한다. auth.users 를 지우거나 그 전체를 목록으로 보여 주는 함수를 만들지 않는다 — 다른 앱 계정이다.
- **운영자는 네 단계다**(`PLAN_GATHERING.md` §24). 수퍼어드민 = `admins`(가입으로는 못 됨, SQL 로만 넣음. 코드·주석의 "전체 운영자". 모든 집회 + 집회관리자 가입 승인). 집회관리자 = `members.status='owner'`(운영자 웹에서 직접 가입 → 수퍼어드민 승인 → 집회 **하나**를 만들어 `gatherings.created_by` 로 관리 — 그 집회의 설정·삭제와 초대 가입자 승인·역할·해제). 보조운영자·운영스탭 = `gathering_admins`(그 집회의 초대 링크 `admin/?join=<코드>` 로 가입·로그인 → `approved=false` 로 대기 → 집회관리자가 승인하면 `role='staff'` 운영스탭, 올려 주면 `role='assistant'` 보조운영자. 이메일 등록은 바로 승인된 운영스탭). 판정은 SQL 함수 셋이다 — 그 집회를 다루는가 `manages(집회id)`(RLS 정책·`save_room_plan`·`admin_add_registration`·`reset_pin`), 설정·이미지·초대 링크를 고치는가 `configures(집회id)`, 삭제·운영자 승인/역할/해제를 하는가 `owns(집회id)`. 만들기는 `can_create()`. 앱은 `remote.scope()` 로 범위(`gatherings`·`configures`·`owned`)를 읽어 집회 목록과 [새 집회]를 가리고, 전역 `canConfigure` 로 운영스탭에게 [집회 설정] 메뉴를 끄며, 집회 설정 화면은 주인일 때만 [집회 삭제]와 운영자 관리 버튼을 켠다.
- `.github/workflows/keepalive.yml` 이 3일마다 DB 를 한 번 읽어 무료 Supabase 프로젝트가 멈추지 않게 한다(저장소 Secrets `SUPABASE_URL`·`SUPABASE_ANON_KEY`).
- 매뉴얼(`docs/manual/`) 스크린샷은 `flutter test --update-goldens tool/manual/shots_test.dart` 로 다시 찍는다(CI 는 `test/` 만 돈다). 화면을 크게 바꾸면 같이 갱신한다.
- `lib/config.dart` 에는 publishable 키만 둔다. 저장소가 공개라서 service_role 키, 실명·실제 전화번호가 든 데이터는 커밋하지 않는다.

**웹 빌드에 같이 들어가는 파일** — `gathering.dart`, `models.dart`, `remote.dart`, `theme.dart`, `widgets/quote_table.dart`, `widgets/duty_tasks.dart`, `widgets/custom_field_input.dart`, `main_public.dart` 는 `dart:io` 를 import 하면 안 된다. `main_public.dart` 는 이 파일들만 가져온다.

**회비 계산은 `gathering.dart` 의 `quote()` 하나뿐이다.** 신청 웹·조회·관리자 화면·참석자 가져오기가 모두 이 함수를 부른다. 따로 계산하면 금액이 어긋난다.
당일 무료 날(`FeeRule.freeDays`, 회비 JSON 안 — 서버 변경 없음)은 그 날 **하루만 당일로** 오면 0원이고, 그 날을 끼고 1박이라도 묵으면 보통 금액이다(`PLAN_GATHERING.md` §18).
**숙박비 별도**(`FeeRule.lodgingSeparate`, 회비 JSON 안 — 서버 변경 없음)를 켜면 `quote()` 가 `_separateLine` 으로 참가비(전체 참석 · 하루 참가=`dayOnly`)와 숙박비(`lodging[구분]` × 묵는 밤)를 따로 센다. 묵는 밤은 신청서의 날짜 줄 [참석][숙박] 체크로 받은 `Person.stays` 이고, 어디서든 `Person.nightsIn()` 으로 읽는다(`stays` 가 없으면 이어진 날로 센다). 기존 집회를 포함해 모든 집회에서 켤 수 있고 **기본은 꺼짐**이다. 끈 집회를 열고 저장해도 회비 JSON 이 바뀌지 않게 `lodgingSeparate` 는 켰을 때만, `lodging` 은 값이 있을 때만 쓴다(`PLAN_GATHERING.md` §20·§22).

**전역 상태** (`lib/main.dart`): `store`(방배정 `Store`, ChangeNotifier), `current`(열어 둔 `Gathering`), `tabIndex`. 탭 번호는 숫자 대신 `settingsTab`/`registrationsTab`/`assignTab` 상수로 쓴다. 서버 호출은 전부 `lib/remote.dart` 의 전역 `remote` 로 하고, 테스트는 여기에 `Remote` 를 상속한 가짜(`FakeRemote`, `PlanRemote`)를 끼운다.

**방배정 저장 흐름** (`Store`)
- 방배정을 바꾸는 코드는 `event` 를 고친 다음 반드시 `store.commit()` 을 부른다. commit 이 알림을 보내고 문서 전체를 저장한다. 저장은 한 번에 하나만 돌고, 저장 중에 또 바뀌면 끝난 뒤 최신 상태로 한 번 더 올린다.
- 동시 편집은 버전으로 막는다. `save_room_plan(p_version)` 이 `CONFLICT` 를 던지면 덮어쓰지 않고 서버 문서를 다시 읽는다.
- `gatheringId == null` 이면 저장하지 않는다(테스트가 이 상태로 돈다). `loadError` 가 있을 때도 저장하지 않는다. 빈 화면으로 서버 내용을 덮어쓰지 않기 위해서다.
- `applyGathering()` 은 집회 설정(이름·날짜·사용자 항목)을 `Event` 에 반영한다. 방배정 쪽 코드는 `Gathering` 을 몰라도 된다.

**집회 구분** (`Gathering.kind`): `집회` / `홈스테이`. 만들 때만 정한다.
- 홈스테이는 신청자가 재워 줄 **가정**이다. 신청하면(입금대기 포함) `Store.syncHomestayRooms` 가 그 이름으로 방을 만들고(`Room.registrationId` 로 신청과 묶는다), 운영자가 따로 등록한 참석자를 그 방에 배치한다. 신청자를 참석자로 가져오지 않는다.
- 방 정원은 신청서의 사용자 정의 항목 `수용 인원`(`homestayCapacityField`)에서 만들 때 한 번만 가져온다. 그 뒤엔 운영자가 고친 값이 이긴다.
- 신청자는 `lookup_registration` 이 같이 돌려주는 `assigned`(`schema.sql` 의 `_assigned`)로 자기 집에 배정된 사람을 본다. 운영자 메모는 빼고 준다.
- 화면은 같은 걸 쓰고 이름만 바꾼다(`방 관리 → 가정 관리`). 홈스테이의 [신청에서 가져오기]는 참석자 화면이 아니라 **가정 관리** 화면에 있다.

**날짜 없는 집회** (`Gathering.dateless`, `gatherings.dateless`): 날짜 대신 사람마다 [참가][미참가]만 받는 집회. 구분이 집회일 때 만들 때만 정한다. 안쪽은 하루짜리 집회(start = end = 기준일)이고 신청 데이터는 새 칸 없이 `Person.days`(참가 = null, 미참가 = `[]`)에 담는다. `quote(dateless: true)` 가 참가 = 참가비(`full`, 비면 `dayOnly`)·미참가 = 0원으로 세고 무료 날·숙박비 별도는 보지 않으며, 전원 미참가면 `Quote.noShow`(그룹당 금액·입금 없음). `Store._wanted` 는 이 집회에서만 0박 참가자도 참석자로 가져온다 — 기존 하루짜리 집회는 그대로 안 가져온다. 방 추가는 이름('1조')도 받는다(`addRoomRange(names: true)`). 화면 판정은 `current.value?.dateless == true` 하나. `toRow` 는 켰을 때만 키를 쓴다. 요구사항은 `PLAN_GATHERING.md` §25.

**기간을 나눈 참석자** (`Attendee.splitOf`): 한 사람이 기간별로 다른 방(홈스테이는 다른 집)에 묵으면 참석자 행이 조각으로 나뉜다. `Store.splitStay`(경계 날짜로 자르기)·`assignRange`(고른 기간만 배정, 나머지는 미배정 조각)가 만들고, 같은 사람은 `Attendee.personId` 로 묶어 화면에서 한 줄로 그린다. 조각도 제 일정을 가진 보통 참석자라 정원·보드·자동배정은 손댈 필요가 없다. 나뉜 조각은 `registrationId` 를 떼고 원본에 `editedByAdmin` 을 붙여 [신청에서 가져오기]가 되돌리지 않게 한다.

**신청서 추가 항목 형식** (`FieldSpec`, `models.dart`): 텍스트·숫자·체크박스·셀렉트박스(보기 목록)·토글 버튼. 이름처럼 방배정 문서(`Event.fieldSpecs`)에 살다가 집회 설정 [저장] 때 `gatherings.field_specs` 로 복사된다. 키가 없으면 텍스트, 값은 형식과 상관없이 `extra` 의 문자열 하나(켜고 끄는 형식은 `fieldOn`='예'). 신청 웹·참석자 편집 창은 `widgets/custom_field_input.dart` 의 `CustomFieldInput` 하나로 그리고, 추가·고치기는 `attendees.dart` 의 `_customFieldDialog` 하나다. `field_specs` 는 칸이 있는 DB 에서 읽었거나 형식이 있을 때만 보낸다(schema.sql 전 DB 에서도 저장이 안 깨지게). 요구사항은 `PLAN_GATHERING.md` §21.

**신청서 기본 항목**: 운영자가 칸마다 [안 받음 | 선택 | 필수]를 정한다. 보통 칸은 뺀 목록(`hidden_fields`)으로,
나중에 생긴 칸(`Gathering.optInFields` = 지금은 `staff`)은 켠 목록(`shown_fields`)으로 관리한다 — 기본이 '안 받음'이라
이미 신청 받는 집회의 신청서가 말없이 바뀌지 않는다. 판정은 `asks()`·`requires()`, 설정 화면의 세그먼트는
`setFieldMode()` 하나가 고친다. 스탭 체크(`Person.staff`)는 확정하면 `Attendee.staff` 로 따라온다.

**담당구역** (`Event.duties`, `lib/screens/duties.dart`): 스탭이 맡을 일(주방·차량…)을 만들고 참석자를 배정한다.
방배정 문서 안에 살아서 서버 변경이 없고 백업에 따라온다. 배정은 **구역이 사람 목록을 든다**(`Duty.personIds`,
`Attendee.personId` 기준) — 한 사람이 여러 구역을 맡을 수 있어서 방배정(`Attendee.roomId`)과 반대다.
`store.membersOf`/`dutiesOf`/`setDutyMembers` 로 읽고 고친다. 요구사항은 `PLAN_GATHERING.md` §15.

**스탭 페이지** (`main_public.dart` 의 `StaffPage`, 링크 `?g=<집회id>&staff=1` = `staffLink()`): 담당구역을 맡은 스탭이
휴대폰+PIN(신청 조회와 같은 관문)으로 들어와 그 구역의 할 일(`Duty.items`, 구분·내용·수량·체크)을 적는다.
신청자는 `room_plans` 에 못 닿으므로 RPC `lookup_duties`·`save_duty_items` 로만 드나든다 — 판정은 신청의
`people[].id` 가 `Duty.personIds` 에 있는지 하나. `save_duty_items` 는 그 구역의 `items` 한 칸만 바꾸므로
스탭이 다른 구역·방배정을 덮어쓸 수 없다(버전 검사는 하지 않는다). 표는 `widgets/duty_tasks.dart` 의
`DutyTaskTable` 한 벌을 스탭 페이지와 운영자 [구역 할일] 화면이 같이 쓴다. 요구사항은 `PLAN_GATHERING.md` §16.

**일정표** (`Gathering.schedule`): `{date, time, title}` 목록을 `gatherings.schedule` 에 담는다. 집회 설정에서 날짜별로 적고, 신청 웹 집회 페이지에 보인다. 기간 밖 날짜의 항목은 화면에 안 보이지만 지우지도 않는다.

**신청 → 참석자** (`Store.syncRegistrations`): 취소되지 않은 신청(**입금대기 포함**)의 사람을 사람 id 로 맞추기 때문에 몇 번을 불러도 결과가 같다. 1박 이상 묵는 사람만 가져오고, 가져올 때 `roomId`·`note` 는 건드리지 않는다. `Attendee.registrationId` 가 null 이면 붙여넣기나 직접 추가로 들어온 사람이라 동기화 대상에서 빠진다. 운영자가 고친 사람은 `editedByAdmin` 으로, 지운 사람은 `Event.deletedIds` 로 기억해 두었다가 `syncConflicts()` 로 어느 쪽 내용을 쓸지 묻는다.
당일(0박)만 오는 신청자는 참석자에 없고 `store.everyone()` 이 신청에서 보태 보여 준다. 참석자 화면에서 고치면 `Event.visitors`(사람 id → 고친 값)에 따로 두고 `everyone()` 이 덮는다 — 참석일·입금 상태는 늘 신청에서 온다. `attendees` 에 넣으면 미배정·자동배정·정원에 섞인다.
입금 상태는 `Attendee.pay`·`Room.pay`(null = 입금확인, `payPending` = 입금대기)에 복사해 두고 정원에는 그대로 센다 — 화면은 `PayBadge`·`store.unpaidIn(room)` 으로 예외만 표시한다.
집회를 열 때·[신청·입금]과 [참석자] 탭이 신청을 읽을 때 `store.syncFromRegistrations()` 가 자동으로 맞춘다. **취소된 신청은 방이 배정돼 있어도 바로 뺀다**(기간을 나눈 조각까지, 홈스테이는 가정을 지우고 손님은 미배정으로). 그 밖에 신청에서 빠진 사람(동반자 삭제 등)은 방이 없을 때만 자동으로 빼고, 방이 있으면 경고를 보여 주는 [신청에서 가져오기]에 맡긴다. 요구사항은 `PLAN_GATHERING.md` §19.

**서버 에러 코드**: SQL 함수가 `CLOSED`, `INVALID_*`, `CONFLICT` 같은 문자열을 던지면(`schema.sql` 맨 위 목록) `remote.dart` 의 `errorText()` 가 안내 문구로 바꾼다. 코드를 새로 만들면 두 곳에 같이 넣는다.

**정원·방 보드**
- 방 인원은 항상 `store.peakOccupancy(room)` 으로 센다. 부분 참석자가 있어서 날짜가 겹치는 밤 중 가장 붐비는 밤을 기준으로 한다. `occupantsOf().length` 로 세면 틀린다.
- 방 상태는 `theme.dart` 의 `statusOf()` 하나로 판정한다.
- 방은 방 관리·방배정·현황 화면 모두 `widgets/room_board.dart` 의 `RoomBoard` 로 그린다. 층마다 `boardColumns`(10)칸 격자이고, 칸 수는 창 폭에 맞춰 줄이지 않는다. `Room.slot` 이 이 폭을 기준으로 저장돼 있기 때문이다. 자리 계산은 `models.dart` 의 `layoutSlots()` 가 맡는다.

**입금 대조** (`lib/bank_import.dart`): 은행 입출금 내역 xlsx 를 `archive`+`xml` 로 직접 읽어(엑셀 패키지 없음) 입금대기 신청과 맞춘다. 쓴 거래는 신청의 `paid_ref` 에 남겨 같은 파일을 다시 올려도 두 번 쓰지 않는다.

**자동배정** (`lib/auto_assign.dart`): 그리디 3단계다(우대 대상 → 그룹을 큰 것부터 → 나머지). 설계 이유는 `PLAN.md` §3.4 에 있다. 미배정 인원만 채우고, 결과는 미리보기를 거친 뒤 적용한다.

## 규칙

- UI 를 만들거나 고칠 때는 `.claude/skills/room-ui/SKILL.md`(room-ui 스킬)를 따른다. 운영자 화면은 휴대폰·태블릿에서도 열린다 — 크기 판정은 `lib/responsive.dart` 하나로 하고 규칙은 스킬 §8, 기획은 `PLAN_RESPONSIVE.md`. 색은 `AppColors` 에서만 가져오고, 폰트는 Pretendard 400~700 만 쓴다(w800 이상 금지). `Material` 에 `shape` 와 `borderRadius` 를 같이 주면 런타임 assert 가 난다.
- 일부러 줄인 설계에는 `ponytail:` 주석으로 한계와 나중에 올릴 방법을 적는다(이미 쓰고 있는 관례). 상태관리·DI·라우터 패키지는 쓰지 않는다. 새 의존성을 넣기 전에 `pubspec.yaml` 에 이미 있는지 먼저 본다. 의존성(패키지·글꼴·CI 액션)을 넣거나 빼면 `README.md` 의 [사용한 오픈소스] 표도 같이 고친다.
