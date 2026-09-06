---
name: room-ui
description: 방배정 앱(Flutter)의 UI를 만들거나 고칠 때 쓰는 디자인 시스템 규칙. 화면 추가/수정, 색·여백·타이포 결정, 방 타일/보드 렌더링, 위젯 스타일 통일이 필요할 때 사용한다.
---

# 방배정 앱 UI 규칙

데스크톱(macOS/Windows) 운영자 도구. 한 화면에서 수백 개의 방·인원을 훑는 게 목적이라
**정보 밀도 > 여백**, **색으로 상태 구분 > 글자로 설명** 이 원칙이다.

## 1. 색은 `lib/theme.dart` 에서만 온다

- 화면 코드에 `Colors.red` 같은 걸 직접 쓰지 않는다. `AppColors.*` / `RoomStatus.*` 를 쓴다.
- 새 색이 필요하면 먼저 `AppColors` 에 이름을 붙이고 쓴다. 이름이 안 붙는 색은 안 쓴다.

## 2. 방 상태는 4가지뿐이고 색이 곧 상태다

| 상태 | 조건 | 색 |
|---|---|---|
| 공실 | `used == 0` | 흰색 타일 |
| 여유 | `0 < used < capacity` | 청록 |
| 만실 | `used == capacity` | 주황 |
| 초과 | `used > capacity` | 빨강 |

- `used` 는 **항상** `store.peakOccupancy(room)` (날짜 겹침 기준 최대 동시 투숙).
  단순 `occupantsOf().length` 를 쓰면 부분 참석자가 있는 방에서 숫자가 틀린다.
- 판정은 `statusOf(used:, capacity:)` 한 함수만 쓴다. 화면마다 조건문을 새로 쓰지 않는다.
- 색만 믿지 않는다. 타일에는 항상 `used/capacity` 숫자와 잔여 막대를 같이 그린다(색각 이상 대비).

## 3. 방은 `RoomBoard` 로 그린다

`lib/widgets/room_board.dart` 의 `RoomBoard` 하나만 쓴다. 방배정 화면과 현황 화면이
서로 다르게 보이면 안 된다.

- 층별로 묶고 **높은 층이 위** (엘리베이터 층 표시와 같은 순서).
- 층 안은 `boardColumns`(10)칸 격자다. **칸 수는 창 폭에 따라 줄이지 않는다** — 방 자리(`Room.slot`)가
  이 폭을 기준으로 저장돼 있어서, 칸 수를 줄이면 운영자가 맞춰둔 건물 배치가 통째로 어긋난다.
  폭이 모자라면 타일을 `_minTile` 까지 줄이고, 그래도 모자라면 보드를 가로로 굴린다.
- 방이 없는 칸은 빈 자리로 남긴다. 복도·엘리베이터·계단 자리라서 지우면 안 된다.
- 자리 배치는 `layoutSlots(rooms, cols)` 한 함수가 정한다. 화면에서 따로 정렬하지 않는다.
- 자리 옮기기(드래그)는 `RoomBoard(editingLayout: true, onMove: ...)` 로 켠다. 옮기는 건
  `store.moveRoom(room, slot, cols: boardColumns)` — 같은 층 안에서만, 겹치면 서로 바꾼다.
- 보드 배경은 어두운 판(`AppColors.board`). 타일 색이 튀어 보이라고 일부러 어둡게 둔다.
- 보드 위에는 `RoomLegend` 를 같이 둔다.

## 4. 여백·모서리·타이포

- 여백 단위는 4의 배수. 카드 안쪽 12~16, 위젯 사이 8, 섹션 사이 20~24.
- 모서리: 타일 10, 카드/보드 14, 버튼·입력 10.
- 그림자 대신 1px 테두리(`AppColors.border`)로 면을 나눈다. `elevation` 은 0.
- 숫자(호수, 인원)는 `FontWeight.w700` 이상. 라벨은 12px `AppColors.textMuted`.

## 5. 화면 구조

- 좌: 조건/필터 패널(고정 폭) · 우: 결과 보드 — 방배정·자동배정 두 화면이 같은 골격.
- 액션 버튼은 `Row + Spacer` 대신 `Wrap` 에 넣는다. 창이 좁아지면 그대로 넘친다(RenderFlex overflow).
- `Material` 에 `shape` 와 `borderRadius` 를 동시에 주면 런타임 assert 로 죽는다. `shape` 만 쓴다.

## 6. 고치고 나서

`flutter analyze && flutter test` 를 돌린다. `test/widget_test.dart` 가 실제로 pump 해서
위 5번 같은 런타임 assert 를 잡아준다. 위젯을 옮기면 이 테스트의 import 부터 확인한다.
