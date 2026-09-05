import 'dart:math' as math;

import 'models.dart';

/// 자동배정 규칙.
class AutoRule {
  AutoRule({
    this.priorityAge = 65,
    this.priorityKeyword,
    this.floorMin,
    this.floorMax,
    this.roomNoMin,
    this.roomNoMax,
    this.separateGender = true,
  });

  /// 나이 >= 이 값이면 우대 대상. null 이면 나이 기준 사용 안 함.
  int? priorityAge;

  /// 참석자 기타사항에 이 문자열이 들어있으면 우대 대상. 예: '강사'
  String? priorityKeyword;

  /// 우대 대상 배정 구역 — 층 범위 또는 호수 범위. 둘 다 null 이면 제한 없음.
  int? floorMin, floorMax;
  int? roomNoMin, roomNoMax;

  bool separateGender;

  bool isPriority(Attendee a) {
    if (priorityAge != null && a.age >= priorityAge!) return true;
    final k = priorityKeyword?.trim();
    if (k != null && k.isNotEmpty && (a.note ?? '').contains(k)) return true;
    return false;
  }

  /// 우대 구역에 속하는 방인가.
  bool inPriorityZone(Room r) {
    final f = r.floor, n = r.roomNumber;
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
  AutoAssignResult(this.assignments, this.unplaced);
  final List<Assignment> assignments;
  final List<Attendee> unplaced;
}

/// 미배정 인원만 채운다. 기존 배정은 건드리지 않는다.
/// 실제 적용은 [applyAssignments] 로 따로 한다 (미리보기 → 적용).
///
/// ponytail: 그리디 3단계 + 호수 근접도만 본다. 최적해가 아니고 O(n·m) 스캔이다.
/// 운영자가 결과를 보고 수동으로 고치는 게 전제 — 불만이 나오면 백트래킹/코스트 함수로 올린다.
AutoAssignResult autoAssign(Event event, AutoRule rule) {
  final nights = event.nights;
  final rooms = [
    ...event.rooms,
  ]..sort((a, b) => (a.roomNumber ?? 999999).compareTo(b.roomNumber ?? 999999));

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
  final roomGroups = <String, Set<String>>{for (final r in rooms) r.id: {}};

  for (final a in event.attendees) {
    if (a.roomId == null || !counts.containsKey(a.roomId)) continue;
    roomGender[a.roomId!] ??= a.gender;
    roomGroups[a.roomId!]!.add(_groupKey(a));
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
    roomGroups[r.id]!.add(_groupKey(a));
    result.add(Assignment(a, r, stage));
  }

  /// 최대 동시 투숙 기준 남은 자리.
  int free(Room r) => r.capacity - counts[r.id]!.fold(0, math.max);

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

  // 2단계: 나머지를 (존, 셀) 그룹으로 묶어 큰 그룹부터.
  final rest = todo.where((a) => !placed.contains(a.id)).toList();
  final groups = <String, List<Attendee>>{};
  for (final a in rest) {
    if (_groupKey(a) == _noGroup) continue; // 존/셀 없음 → 3단계로
    groups.putIfAbsent(_groupKey(a), () => []).add(a);
  }
  final orderedGroups = groups.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  for (final g in orderedGroups) {
    for (final a in g.value) {
      // 같은 그룹이 이미 들어간 방들의 호수 = 근접도 기준점
      final anchors = rooms
          .where((r) => roomGroups[r.id]!.contains(g.key))
          .map((r) => r.roomNumber)
          .whereType<int>()
          .toList();
      final candidates = rooms.where((r) => fits(r, a)).toList()
        ..sort((x, y) {
          final d = _dist(x, anchors).compareTo(_dist(y, anchors));
          if (d != 0) return d;
          return free(y).compareTo(free(x));
        });
      final room = candidates.firstOrNull;
      if (room != null) {
        place(room, a, '그룹');
        placed.add(a.id);
      }
    }
  }

  // 3단계: 남은 인원 → 성별 맞는 빈자리 아무 데나 (여유 많은 방부터).
  for (final a in todo.where((a) => !placed.contains(a.id))) {
    final candidates = rooms.where((r) => fits(r, a)).toList()
      ..sort((x, y) => free(y).compareTo(free(x)));
    if (candidates.isNotEmpty) {
      place(candidates.first, a, '잔여');
      placed.add(a.id);
    }
  }

  return AutoAssignResult(
    result,
    todo.where((a) => !placed.contains(a.id)).toList(),
  );
}

void applyAssignments(List<Assignment> assignments) {
  for (final x in assignments) {
    x.attendee.roomId = x.room.id;
  }
}

const _noGroup = '/';

String _groupKey(Attendee a) => '${a.zone ?? ''}/${a.cell ?? ''}';

/// 기준 호수들과의 최소 거리. 기준이 없으면 0 (거리 무시).
int _dist(Room r, List<int> anchors) {
  if (anchors.isEmpty) return 0;
  final n = r.roomNumber;
  if (n == null) return 1 << 20;
  return anchors.map((a) => (n - a).abs()).reduce(math.min);
}
