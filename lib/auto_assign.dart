import 'dart:math' as math;

import 'models.dart';

/// 자동배정에서 "같은 값이면 같이 붙여줄" 기준이 될 수 있는 참석자 항목.
///
/// 참석자에 새 항목(예: 교회)이 생기면 여기에 한 줄만 추가하면 화면까지 따라온다.
class GroupField {
  const GroupField(this.key, this.label);

  /// 운영자가 만든 항목. 이름이 곧 키이자 라벨이다.
  GroupField.custom(String name) : key = 'x:$name', label = name;

  /// 'zone' | 'cell' | 'note' | 'x:<사용자 항목 이름>'
  final String key;
  final String label;

  static const zone = GroupField('zone', '존');
  static const cell = GroupField('cell', '셀');
  static const note = GroupField('note', '기타');

  /// 같은 신청(가족·동반자)끼리. 값은 신청 id 라 화면에는 이름만 보여준다.
  static const family = GroupField('family', '가족');
  static const builtins = [zone, cell, note, family];

  /// 이 집회에서 고를 수 있는 기준 전체 = 기본 + 사용자 정의 항목.
  static List<GroupField> forEvent(Event e) => [
    ...builtins,
    ...e.customFields.map(GroupField.custom),
  ];

  String? of(Attendee a) => switch (key) {
    'zone' => a.zone,
    'cell' => a.cell,
    'note' => a.note,
    'family' => a.registrationId,
    _ => a.extra[label],
  };

  @override
  bool operator ==(Object other) => other is GroupField && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'GroupField($key)';
}

/// 자동배정 규칙.
class AutoRule {
  AutoRule({
    this.priorityAge = 65,
    this.priorityKeyword,
    this.floorMin,
    this.floorMax,
    this.roomNoMin,
    this.roomNoMax,
    this.priorityBuilding,
    this.buildings,
    this.separateGender = true,
    List<GroupField>? groupBy,
  }) : groupBy = groupBy ?? const [GroupField.zone, GroupField.cell];

  /// 나이 >= 이 값이면 우대 대상. null 이면 나이 기준 사용 안 함.
  int? priorityAge;

  /// 참석자 기타사항에 이 문자열이 들어있으면 우대 대상. 예: '강사'
  String? priorityKeyword;

  /// 우대 대상 배정 구역 — 층 범위 또는 호수 범위. 둘 다 null 이면 제한 없음.
  int? floorMin, floorMax;
  int? roomNoMin, roomNoMax;

  /// 우대 구역을 이 건물로 좁힌다. null = 건물 상관없음.
  String? priorityBuilding;

  /// 배정에 쓸 건물 (건물 없는 방은 null). null = 전부.
  /// 여기 없는 건물의 방에는 아무도 새로 넣지 않는다 (이미 있는 사람은 그대로).
  Set<String?>? buildings;

  bool separateGender;

  /// 같이 배정할 기준을 **우선순위 순서대로**. 앞에 있을수록 중요하다.
  ///
  /// 예: `[zone, cell]` 이면 존과 셀이 모두 같은 사람을 한 방에 모으고,
  /// 자리가 모자라 다 못 모으면 **뒤쪽 기준(셀)부터 포기**하고 최소한 존이라도 맞춘다.
  List<GroupField> groupBy;

  /// [a] 의 그룹 키를 우선순위 [level] 개까지만 이어붙인 것.
  /// 값이 빈 항목을 만나면 거기서 끊는다 (빈 값끼리는 같은 그룹이 아니다).
  /// level 0 이거나 첫 항목부터 비어 있으면 null = 그룹 없음.
  String? keyOf(Attendee a, [int? level]) {
    final n = (level ?? groupBy.length).clamp(0, groupBy.length);
    final parts = <String>[];
    for (var i = 0; i < n; i++) {
      final v = groupBy[i].of(a)?.trim() ?? '';
      if (v.isEmpty) break;
      parts.add('${groupBy[i].key}=$v');
    }
    return parts.isEmpty ? null : parts.join('\u0001');
  }

  /// [a] 가 실제로 가진 그룹 깊이 (빈 값 앞까지).
  int depthOf(Attendee a) {
    var d = 0;
    for (final f in groupBy) {
      if ((f.of(a)?.trim() ?? '').isEmpty) break;
      d++;
    }
    return d;
  }

  bool isPriority(Attendee a) {
    if (priorityAge != null && a.age >= priorityAge!) return true;
    final k = priorityKeyword?.trim();
    if (k != null && k.isNotEmpty && (a.note ?? '').contains(k)) return true;
    return false;
  }

  /// 우대 구역에 속하는 방인가.
  bool inPriorityZone(Room r) {
    final f = r.floor, n = r.roomNumber;
    if (priorityBuilding != null && r.building != priorityBuilding) {
      return false;
    }
    if (floorMin != null && (f == null || f < floorMin!)) return false;
    if (floorMax != null && (f == null || f > floorMax!)) return false;
    if (roomNoMin != null && (n == null || n < roomNoMin!)) return false;
    if (roomNoMax != null && (n == null || n > roomNoMax!)) return false;
    return true;
  }
}

/// 자동배정 결과 한 건 (미리보기용).
class Assignment {
  Assignment(this.attendee, this.room, this.stage);
  final Attendee attendee;
  final Room room;

  /// '우대' | '그룹' | '잔여'
  final String stage;
}

class AutoAssignResult {
  AutoAssignResult(
    this.assignments,
    this.unplaced, {
    this.priorityOutsideZone = const [],
  });

  final List<Assignment> assignments;
  final List<Attendee> unplaced;

  /// 우대 대상인데 지정한 층/호수 범위에 자리가 없어 다른 곳에 배정된 사람들.
  /// 구역을 잡아놨는데 결과가 딴 층이면 운영자가 이유를 알아야 한다.
  final List<Attendee> priorityOutsideZone;
}

/// 미배정 인원만 채운다. 기존 배정은 건드리지 않는다.
/// 실제 적용은 [applyAssignments] 로 따로 한다 (미리보기 → 적용).
///
/// ponytail: 그리디 3단계 + 호수 근접도만 본다. 최적해가 아니고 O(n·m) 스캔이다.
/// 운영자가 결과를 보고 수동으로 고치는 게 전제 — 불만이 나오면 백트래킹/코스트 함수로 올린다.
AutoAssignResult autoAssign(Event event, AutoRule rule) {
  final nights = event.nights;
  final allowed = rule.buildings;
  final rooms = [
    for (final r in event.rooms)
      if (allowed == null || allowed.contains(r.building)) r,
  ]..sort(byRoomNo);

  // 방별 밤별 현재 인원. 기존 배정에서 시작.
  final counts = {
    for (final r in rooms)
      r.id: occupancyByNight(
        event.attendees.where((a) => a.roomId == r.id),
        nights,
      ),
  };
  // 방의 유효 성별: 지정된 성별, 없으면 첫 배정자 성별로 굳는다.
  final roomGender = {for (final r in rooms) r.id: r.gender};
  // 방에 이미 들어있는 (존, 셀) 그룹 → 근접도 기준점.
  // 방마다 그 방에 들어있는 사람들의 그룹 키를 우선순위 단계별로 모두 담는다.
  // (1단계 키, 1~2단계 키, ...) 를 다 넣어두면 "존만 같은 방" 도 찾을 수 있다.
  final roomKeys = <String, Set<String>>{for (final r in rooms) r.id: {}};

  void remember(String roomId, Attendee a) {
    final d = rule.depthOf(a);
    if (d == 0) {
      roomKeys[roomId]!.add(_looseKey);
      return;
    }
    for (var lv = 1; lv <= d; lv++) {
      final k = rule.keyOf(a, lv);
      if (k != null) roomKeys[roomId]!.add(k);
    }
  }

  final result = <Assignment>[];

  bool fits(Room r, Attendee a) {
    if (rule.separateGender) {
      final g = roomGender[r.id];
      if (g != null && g != a.gender) return false;
    }
    final c = counts[r.id]!;
    final stays = stayMask(a, nights);
    for (var i = 0; i < nights.length; i++) {
      if (stays[i] && c[i] + 1 > r.capacity) return false;
    }
    return true;
  }

  void place(Room r, Attendee a, String stage) {
    final c = counts[r.id]!;
    final stays = stayMask(a, nights);
    for (var i = 0; i < nights.length; i++) {
      if (stays[i]) c[i]++;
    }
    roomGender[r.id] ??= a.gender;
    remember(r.id, a);
    result.add(Assignment(a, r, stage));
  }

  /// 최대 동시 투숙 기준 남은 자리.
  int free(Room r) => r.capacity - counts[r.id]!.fold(0, math.max);

  /// [a] 와 같은 그룹이 이미 들어있는 방들. 우선순위가 깊은 단계부터 찾아 내려간다.
  /// (존+셀이 같은 방) 이 없으면 (존만 같은 방) 이라도 찾는다.
  List<Room> sameGroupRooms(Attendee a) {
    final depth = rule.depthOf(a);
    if (depth == 0) {
      return rooms.where((r) => roomKeys[r.id]!.contains(_looseKey)).toList();
    }
    for (var lv = depth; lv >= 1; lv--) {
      final key = rule.keyOf(a, lv);
      if (key == null) continue;
      final hit = rooms.where((r) => roomKeys[r.id]!.contains(key)).toList();
      if (hit.isNotEmpty) return hit;
    }
    return const [];
  }

  bool isEmptyRoom(Room r) => counts[r.id]!.every((c) => c == 0);

  /// [a] 를 넣을 방을 고른다. 없으면 null.
  ///
  /// 방 고르는 순서가 이 알고리즘의 핵심이다:
  ///   0등급 같은 그룹이 이미 있는 방 → 그 방부터 꽉 채운다
  ///   1등급 아무도 없는 빈 방       → 새 그룹은 남의 방에 끼지 말고 빈 방을 연다
  ///   2등급 다른 그룹이 있는 방     → 빈 방이 동나야 비로소 섞는다
  /// 같은 등급 안에서는 (같은 그룹 방과 가까운 호수) → (덜 남은 방) → (낮은 호수).
  Room? pickRoom(Attendee a) {
    final same = sameGroupRooms(a);
    final sameIds = same.map((r) => r.id).toSet();

    int tier(Room r) => sameIds.contains(r.id)
        ? 0
        : isEmptyRoom(r)
        ? 1
        : 2;

    final candidates = rooms.where((r) => fits(r, a)).toList()
      ..sort((x, y) {
        final t = tier(x).compareTo(tier(y));
        if (t != 0) return t;
        // 빈 방을 새로 열 때는 낮은 호수(=낮은 층)부터. 운영자가 예측할 수 있게.
        if (tier(x) == 1) return byRoomNo(x, y);
        final d = _dist(x, same).compareTo(_dist(y, same));
        if (d != 0) return d;
        final f = free(x).compareTo(free(y));
        return f != 0 ? f : byRoomNo(x, y);
      });
    return candidates.firstOrNull;
  }

  for (final a in event.attendees) {
    if (a.roomId == null || !counts.containsKey(a.roomId)) continue;
    roomGender[a.roomId!] ??= a.gender;
    remember(a.roomId!, a);
  }

  final todo = event.attendees.where((a) => a.roomId == null).toList();

  // 1단계: 우대 대상 → 지정 구역. 나이 많은 순, 낮은 층 먼저.
  final priority = todo.where(rule.isPriority).toList()
    ..sort((a, b) => b.age.compareTo(a.age));
  final zone = rooms.where(rule.inPriorityZone).toList();
  final placed = <String>{};
  for (final a in priority) {
    for (final r in zone) {
      if (fits(r, a)) {
        place(r, a, '우대');
        placed.add(a.id);
        break;
      }
    }
  }
  // 지정 구역에 못 들어간 우대 대상. 아래 단계에서 일반 인원처럼 배정된다.
  final outsideZone = priority.where((a) => !placed.contains(a.id)).toList();

  // 2단계: 나머지를 (존, 셀) 그룹으로 묶어 큰 그룹부터.
  final rest = todo.where((a) => !placed.contains(a.id)).toList();
  final groups = <String, List<Attendee>>{};
  for (final a in rest) {
    final k = rule.keyOf(a);
    if (k == null) continue; // 기준 값이 하나도 없음 → 3단계로
    groups.putIfAbsent(k, () => []).add(a);
  }
  final orderedGroups = groups.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  for (final g in orderedGroups) {
    for (final a in g.value) {
      final room = pickRoom(a);
      if (room != null) {
        place(room, a, '그룹');
        placed.add(a.id);
      }
    }
  }

  // 3단계: 그룹 기준 값이 없는 사람들. 이들끼리도 한 방에 모으고(무소속끼리는 같은 그룹),
  // 다른 그룹의 방에는 빈 방이 없을 때만 들어간다.
  for (final a in todo.where((a) => !placed.contains(a.id))) {
    final room = pickRoom(a);
    if (room != null) {
      place(room, a, '잔여');
      placed.add(a.id);
    }
  }

  return AutoAssignResult(
    result,
    todo.where((a) => !placed.contains(a.id)).toList(),
    priorityOutsideZone: outsideZone,
  );
}

void applyAssignments(List<Assignment> assignments) {
  for (final x in assignments) {
    x.attendee.roomId = x.room.id;
  }
}

/// 그룹 기준 값이 하나도 없는 사람들이 공유하는 키. 이들끼리는 같은 그룹으로 본다.
const _looseKey = '\u0000loose';

/// 기준 방들과의 최소 호수 거리. 기준이 없으면 0 (거리 무시).
/// 다른 건물의 방은 호수가 가까워도 멀리 있는 것으로 본다.
int _dist(Room r, List<Room> anchors) {
  if (anchors.isEmpty) return 0;
  final n = r.roomNumber;
  final near = [
    for (final a in anchors)
      if (a.building == r.building) ?a.roomNumber,
  ];
  if (n == null || near.isEmpty) return 1 << 20;
  return near.map((a) => (n - a).abs()).reduce(math.min);
}

/// 운영자가 고른 [people] 을 운영자가 고른 [rooms] 에 호수 순으로 채워 넣는다.
/// (예: "에클레시아셀 6명" 을 301~304호에 배정)
///
/// - 정원은 날짜 겹침 기준으로 지킨다. 자리가 모자란 사람은 [AutoAssignResult.unplaced] 로 돌려준다.
/// - [overflow] 가 true 면 남은 사람을 가장 덜 찬 방부터 정원을 넘겨서라도 넣는다.
/// - 성별은 보지 않는다. 방을 직접 고른 건 운영자이므로 그 판단을 덮어쓰지 않는다.
///
/// 이미 대상 방에 배정돼 있던 사람은 자기 자리를 두 번 세지 않는다.
AutoAssignResult distribute(
  Event event,
  List<Attendee> people,
  List<Room> rooms, {
  bool overflow = false,
}) {
  final nights = event.nights;
  final ordered = [...rooms]..sort(byRoomNo);
  final moving = people.map((a) => a.id).toSet();

  final counts = {
    for (final r in ordered)
      r.id: occupancyByNight(
        event.attendees.where(
          (a) => a.roomId == r.id && !moving.contains(a.id),
        ),
        nights,
      ),
  };

  final result = <Assignment>[];
  final leftover = <Attendee>[];

  bool fits(Room r, List<bool> stays) {
    final c = counts[r.id]!;
    for (var i = 0; i < nights.length; i++) {
      if (stays[i] && c[i] + 1 > r.capacity) return false;
    }
    return true;
  }

  void place(Room r, Attendee a, List<bool> stays) {
    final c = counts[r.id]!;
    for (var i = 0; i < nights.length; i++) {
      if (stays[i]) c[i]++;
    }
    result.add(Assignment(a, r, '지정'));
  }

  for (final a in people) {
    final stays = stayMask(a, nights);
    final room = ordered.where((r) => fits(r, stays)).firstOrNull;
    if (room != null) {
      place(room, a, stays);
    } else {
      leftover.add(a);
    }
  }

  if (!overflow || ordered.isEmpty) {
    return AutoAssignResult(result, leftover);
  }

  // 초과 배정: 그 시점에 가장 덜 찬 방으로.
  for (final a in leftover) {
    final stays = stayMask(a, nights);
    final room = ordered.reduce(
      (x, y) =>
          counts[x.id]!.fold(0, math.max) <= counts[y.id]!.fold(0, math.max)
          ? x
          : y,
    );
    place(room, a, stays);
  }
  return AutoAssignResult(result, const []);
}
