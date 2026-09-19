import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'gathering.dart';
import 'models.dart';
import 'remote.dart';

/// 앱 전체 상태. 집회 하나의 방배정(방·참석자·배정)을 서버 문서 하나로 통째로 읽고 쓴다.
/// 여러 PC·태블릿이 같은 문서를 연다. 동시에 고치면 버전으로 막는다 (schema.sql save_room_plan).
/// ponytail: 변경마다 문서 전체를 올린다. 참석자 수천 명(1MB 미만)까지는 문제없다.
class Store extends ChangeNotifier {
  /// 열어 둔 집회 id. null 이면 아무것도 안 연 상태 — 저장하지 않는다 (테스트도 이 상태).
  String? gatheringId;

  Event event = Event(
    name: '새 집회',
    startDate: dateOnly(DateTime.now()),
    endDate: dateOnly(DateTime.now()).add(const Duration(days: 3)),
  );

  /// 마지막으로 읽거나 저장한 서버 문서의 버전. 0 = 서버에 아직 없음.
  int version = 0;

  bool loaded = false;

  /// 불러오기 실패 이유. 이때는 저장하지 않는다 — 빈 화면으로 서버 내용을 덮어쓰면 안 된다.
  String? loadError;

  /// 마지막 저장이 실패했거나 충돌했으면 그 이유. 화면 위 경고 줄에 뜬다.
  String? saveError;

  /// 집회 하나의 방배정을 연다. 서버에 아직 없으면 [fallback] 으로 시작한다.
  Future<void> open(String gatheringId, Event fallback) async {
    await pendingWrites;
    this.gatheringId = gatheringId;
    event = fallback;
    version = 0;
    loadError = null;
    saveError = null;
    loaded = false;
    await load();
  }

  /// 서버에서 다시 읽는다.
  Future<void> load() async {
    try {
      final p = await remote.roomPlan(gatheringId!);
      if (p != null) {
        event = Event.fromJson(p.data);
        version = p.version;
      }
      loadError = null;
    } catch (e) {
      loadError =
          '방배정을 불러오지 못했습니다. 인터넷 연결을 확인하고 집회를 다시 여세요. '
          '그동안 고친 내용은 저장되지 않습니다.\n${errorText(e)}';
    }
    loaded = true;
    notifyListeners();
  }

  bool _dirty = false;
  Future<void>? _saving;

  /// 변경 후 저장 + 알림. UI는 이것만 부르면 된다.
  /// 저장은 한 번에 하나 — 올리는 중에 또 바뀌면 끝난 뒤 최신 상태로 한 번 더 올린다.
  void commit() {
    notifyListeners();
    _dirty = true;
    _saving ??= _flush().whenComplete(() => _saving = null);
  }

  /// 테스트/집회 전환 때 저장이 끝날 때까지 기다린다.
  Future<void> get pendingWrites => _saving ?? Future.value();

  Future<void> _flush() async {
    while (_dirty && gatheringId != null && loadError == null) {
      _dirty = false;
      try {
        version = await remote.saveRoomPlan(
          gatheringId!,
          event.toJson(),
          version,
        );
        saveError = null;
      } catch (e) {
        if (isConflict(e)) {
          // 다른 기기가 먼저 저장했다. 덮어쓰지 않고 그쪽 내용으로 바꾼다.
          await load();
          saveError = '다른 기기에서 먼저 저장해 최신 내용을 다시 불러왔습니다. 방금 한 변경은 다시 해주세요.';
        } else {
          _dirty = true; // 다음 변경 때 문서 전체를 다시 올린다
          saveError =
              '저장하지 못했습니다. 인터넷이 돌아오면 다음 변경 때 다시 저장합니다. '
              '불안하면 [백업]으로 내려받아 두세요.\n${errorText(e)}';
          break;
        }
      }
    }
    notifyListeners();
  }

  // --- 집회 설정 · 신청 → 방배정 ---

  /// 집회 설정(서버)을 방배정에 반영한다. 방배정 쪽 코드는 [Event] 만 본다.
  /// 바뀐 게 없으면 저장하지 않는다 — 여는 것만으로 버전이 오르면 다른 기기와 괜히 충돌한다.
  void applyGathering(Gathering g) {
    final s = dateOnly(g.start), e = dateOnly(g.end);
    final end = e.isAfter(s) ? e : s.add(const Duration(days: 1));
    final changed =
        event.name != g.name || event.startDate != s || event.endDate != end;
    event
      ..name = g.name
      ..startDate = s
      ..endDate = end;
    if (_addFields(g.formFields) > 0 || changed) commit();
  }

  /// 확정된 신청의 사람들 (사람 id → 참석자). 당일(0박) 참석자는 방이 필요 없어 뺀다.
  Map<String, Attendee> _wanted(Gathering g, List<Registration> regs) => {
    for (final r in regs)
      if (r.status == RegStatus.confirmed)
        for (final line in g.quoteFor(r.people, r.createdAt).lines)
          if (line.nights > 0) line.person.id: attendeeOf(g, r, line.person),
  };

  /// 신청의 한 사람 → 참석자. [p] 는 집회 기간 안에 오는 날이 하루 이상 있어야 한다.
  /// 당일(0박)만 오는 사람은 체크인 = 체크아웃 = 그날이 된다. 이런 사람은 참석자 화면의
  /// 날짜별(식수) 통계에만 쓰고 방배정 참석자로는 넣지 않는다([_wanted]).
  Attendee attendeeOf(Gathering g, Registration r, Person p) {
    final days = p.daysIn(g.start, g.end);
    final nights = nightsOf(days);
    final last = nights.lastOrNull;
    final gap =
        nights.isNotEmpty && nightsOf(nights).length != nights.length - 1;
    return Attendee(
      id: p.id,
      name: p.name,
      gender: p.gender,
      age: p.birthYear == 0 ? 0 : g.start.year - p.birthYear, // 0 = 모름
      phone: fmtPhone(p.phone ?? r.phone),
      cell: p.cell,
      zone: p.zone,
      checkIn: nights.firstOrNull ?? days.first,
      checkOut: last == null
          ? days.first
          : DateTime(last.year, last.month, last.day + 1),
      stayNights: gap ? nights : null,
      extra: {...p.extra},
      registrationId: r.id,
    );
  }

  /// [syncRegistrations] 를 하면 지워질 사람 중 방이 배정된 사람. 지우기 전에 운영자에게 보여준다.
  List<Attendee> syncWouldRemove(Gathering g, List<Registration> regs) {
    final want = _wanted(g, regs);
    return event.attendees
        .where(
          (a) =>
              a.registrationId != null &&
              !want.containsKey(a.id) &&
              a.roomId != null,
        )
        .toList();
  }

  /// 운영자가 직접 고쳤는데 신청 내용과 다른 사람 / 직접 지웠는데 신청에는 아직 있는 사람.
  /// [syncRegistrations] 전에 운영자에게 어느 쪽을 쓸지 묻는다.
  ({List<Attendee> edited, List<Attendee> deleted}) syncConflicts(
    Gathering g,
    List<Registration> regs,
  ) {
    final want = _wanted(g, regs);
    return (
      edited: [
        for (final a in event.attendees)
          if (a.editedByAdmin &&
              want[a.id] != null &&
              !_sameSource(a, want[a.id]!))
            a,
      ],
      deleted: [
        for (final w in want.values)
          if (event.deletedIds.contains(w.id)) w,
      ],
    );
  }

  /// 확정된 신청을 참석자로 맞춘다. 몇 번 불러도 결과가 같다 (사람 id 로 맞춘다).
  ///
  /// - 신청에서 온 항목(이름·성별·나이·전화·셀·존·사용자 항목·일정)만 덮어쓰고
  ///   배정된 방(roomId)·기타(note)는 그대로 둔다.
  /// - 신청에서 왔는데 이제 확정 목록에 없는 사람(취소·되돌림·동반자 삭제)은 지운다.
  ///   [remove] 가 false 면 지우지 않는다 — 입금 확인 때 자동으로 부를 때. 방 배정이
  ///   말없이 풀리면 안 되므로, 지우는 건 경고를 보여주는 [신청에서 가져오기]에서만 한다.
  /// - 붙여넣기·직접 추가한 사람(registrationId == null)은 건드리지 않는다.
  /// - 운영자가 직접 고치거나 지운 사람([syncConflicts])은 [keepAdminEdits] 면 그대로 두고,
  ///   아니면 신청 내용으로 덮어쓰거나 되살린다.
  ({int added, int updated, int removed, int dayOnly}) syncRegistrations(
    Gathering g,
    List<Registration> regs, {
    bool remove = true,
    bool keepAdminEdits = true,
  }) {
    final want = _wanted(g, regs);
    final confirmedPeople = regs
        .where((r) => r.status == RegStatus.confirmed)
        .fold(0, (s, r) => s + r.people.length);
    final have = {for (final a in event.attendees) a.id: a};
    var added = 0, updated = 0;
    for (final w in want.values) {
      final a = have[w.id];
      if (a == null) {
        if (event.deletedIds.contains(w.id)) {
          if (keepAdminEdits) continue;
          event.deletedIds.remove(w.id);
        }
        event.attendees.add(w);
        added++;
      } else if (!_sameSource(a, w)) {
        if (a.editedByAdmin && keepAdminEdits) continue;
        a
          ..name = w.name
          ..gender = w.gender
          ..age = w.age
          ..phone = w.phone
          ..cell = w.cell
          ..zone = w.zone
          ..checkIn = w.checkIn
          ..checkOut = w.checkOut
          ..stayNights = w.stayNights
          ..extra = w.extra
          ..registrationId = w.registrationId
          ..editedByAdmin = false;
        updated++;
      }
    }
    final before = event.attendees.length;
    if (remove) {
      event.attendees.removeWhere(
        (a) => a.registrationId != null && !want.containsKey(a.id),
      );
    }
    final removed = before - event.attendees.length;
    final newFields = _addFields(want.values.expand((a) => a.extra.keys));
    if (added + updated + removed + newFields > 0) commit();
    return (
      added: added,
      updated: updated,
      removed: removed,
      dayOnly: confirmedPeople - want.length,
    );
  }

  // --- 홈스테이: 신청 → 방(가정) ---

  /// 확정된 신청 1건 = 방 1개. 몇 번 불러도 결과가 같다 (신청 id 로 맞춘다).
  ///
  /// - 방 이름은 신청자 이름, 정원은 신청서의 '수용 인원'([homestayCapacityField], 기본
  ///   [defaultHomeCapacity]), 기타는 전화번호.
  /// - 이미 있는 방은 **이름만** 맞춘다. 정원·기타·자리는 운영자가 고친 것이 이긴다
  ///   (신청자는 확정 뒤 신청을 못 고치므로 정원은 만들 때 한 번이면 충분하다).
  /// - [remove] 가 false 면 확정이 풀린 신청의 방을 지우지 않는다 — 확정 버튼이 자동으로
  ///   부를 때. 방이 말없이 사라지면 안 되므로, 지우는 건 경고를 보여주는 [신청에서 가져오기]에서만.
  ({int added, int updated, int removed}) syncHomestayRooms(
    Gathering g,
    List<Registration> regs, {
    bool remove = true,
  }) {
    final want = {
      for (final r in regs)
        if (r.status == RegStatus.confirmed) r.id: r,
    };
    final have = {
      for (final room in event.rooms)
        if (room.registrationId != null) room.registrationId!: room,
    };
    var added = 0, updated = 0;
    for (final r in want.values) {
      final room = have[r.id];
      if (room == null) {
        event.rooms.add(
          Room(
            id: newId(),
            roomNo: r.applicant,
            capacity: homeCapacityOf(r),
            note: fmtPhone(r.phone),
            registrationId: r.id,
          ),
        );
        added++;
      } else if (room.roomNo != r.applicant) {
        room.roomNo = r.applicant;
        updated++;
      }
    }
    var removed = 0;
    if (remove) {
      for (final room in [...event.rooms]) {
        final id = room.registrationId;
        if (id == null || want.containsKey(id)) continue;
        deleteRoom(room); // 배정돼 있던 사람은 미배정으로 돌아간다
        removed++;
      }
    }
    if (added + updated > 0) commit();
    return (added: added, updated: updated, removed: removed);
  }

  /// [syncHomestayRooms] 를 하면 지워질 방 중 사람이 배정된 방. 지우기 전에 보여준다.
  List<Room> homestayWouldRemove(Gathering g, List<Registration> regs) {
    final want = {
      for (final r in regs)
        if (r.status == RegStatus.confirmed) r.id,
    };
    return [
      for (final room in event.rooms)
        if (room.registrationId != null &&
            !want.contains(room.registrationId) &&
            occupantsOf(room).isNotEmpty)
          room,
    ];
  }

  /// 신청 [registrationId] 에서 온 것을 방배정에서 뺀다 (신청 취소·삭제 때).
  /// 집회는 그 신청의 참석자를, 홈스테이는 그 신청으로 만든 방(가정)을 뺀다.
  /// 붙여넣기·직접 추가한 사람은 신청 id 가 없으니 건드리지 않는다.
  ({int people, int rooms}) removeRegistration(String registrationId) {
    final rooms = [
      for (final r in event.rooms)
        if (r.registrationId == registrationId) r,
    ];
    for (final r in rooms) {
      deleteRoom(r); // 배정돼 있던 사람은 미배정으로 돌아간다
    }
    final before = event.attendees.length;
    event.attendees.removeWhere((a) => a.registrationId == registrationId);
    final n = before - event.attendees.length;
    if (n > 0) commit();
    return (people: n, rooms: rooms.length);
  }

  /// 이 신청을 취소·삭제하면 방 배정이 풀리는 사람들.
  /// 집회는 그 신청으로 온 사람, 홈스테이는 그 가정에 배정된 손님.
  List<Attendee> wouldLoseRoom(String registrationId) {
    final roomIds = {
      for (final r in event.rooms)
        if (r.registrationId == registrationId) r.id,
    };
    return [
      for (final a in event.attendees)
        if (a.roomId != null &&
            (roomIds.contains(a.roomId) || a.registrationId == registrationId))
          a,
    ];
  }

  bool _sameSource(Attendee a, Attendee b) =>
      a.name == b.name &&
      a.gender == b.gender &&
      a.age == b.age &&
      a.phone == b.phone &&
      a.cell == b.cell &&
      a.zone == b.zone &&
      a.checkIn == b.checkIn &&
      a.checkOut == b.checkOut &&
      listEquals(a.stayNights, b.stayNights) &&
      a.registrationId == b.registrationId &&
      mapEquals(a.extra, b.extra);

  /// 모르는 사용자 정의 항목 이름을 추가한다. 추가한 개수.
  int _addFields(Iterable<String> names) {
    var n = 0;
    for (final f in names) {
      if (f.trim().isEmpty ||
          event.customFields.contains(f) ||
          builtinFieldLabels.values.contains(f)) {
        continue;
      }
      event.customFields.add(f);
      n++;
    }
    return n;
  }

  // --- id ---
  int _seq = 0;
  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';

  // --- 조회 헬퍼 ---
  Room? roomById(String? id) => id == null
      ? null
      : event.rooms.cast<Room?>().firstWhere(
          (r) => r!.id == id,
          orElse: () => null,
        );

  List<Attendee> occupantsOf(Room room) =>
      event.attendees.where((a) => a.roomId == room.id).toList();

  /// 날짜 겹침 기준 최대 동시 투숙 인원.
  int peakOccupancy(Room room) =>
      occupancyByNight(occupantsOf(room), event.nights).fold(0, math.max);

  /// 방에 들어있는 그룹(셀 우선, 없으면 존)별 인원 요약. 예: "에클레시아 4 · 믿음셀 2"
  /// 방 하나에 어느 단체가 들어있는지 한 줄로 보여줄 때 쓴다.
  String groupSummary(Room room) {
    final counts = <String, int>{};
    for (final a in occupantsOf(room)) {
      final key = (a.cell ?? '').isNotEmpty
          ? a.cell!
          : (a.zone ?? '').isNotEmpty
          ? a.zone!
          : '소속없음';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  /// 해당 밤들 중 가장 붐비는 시점 기준 남은 자리. 음수면 초과.
  int freeSeats(Room room) => room.capacity - peakOccupancy(room);

  int get totalCapacity => event.rooms.fold(0, (s, r) => s + r.capacity);

  List<Attendee> get unassigned =>
      event.attendees.where((a) => a.roomId == null).toList();

  /// 이름/셀/존/전화 통합 검색. [among] 을 주면 그 사람들 안에서 찾는다 (기본 = 참석자 전체).
  List<Attendee> search(String q, [Iterable<Attendee>? among]) {
    final from = among ?? event.attendees;
    final k = q.trim().toLowerCase();
    if (k.isEmpty) return [...from];
    return from.where((a) {
      return [
        a.name,
        a.cell,
        a.zone,
        a.phone,
        a.note,
        ...a.extra.values, // 사용자 정의 항목(교회 등)도 같이 검색된다
      ].any((f) => (f ?? '').toLowerCase().contains(k));
    }).toList();
  }

  // --- 변경 ---
  // --- 사용자 정의 참석자 항목 ---

  /// 항목 추가. 이미 있거나 기본 항목과 이름이 겹치면 false.
  bool addCustomField(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (event.customFields.contains(n)) return false;
    if (builtinFieldLabels.values.contains(n)) return false;
    event.customFields.add(n);
    commit();
    return true;
  }

  /// 항목 삭제. 참석자들이 갖고 있던 값도 같이 지운다.
  void removeCustomField(String name) {
    event.customFields.remove(name);
    for (final a in event.attendees) {
      a.extra.remove(name);
    }
    commit();
  }

  /// 항목 이름 변경. 참석자들의 값 키도 같이 옮긴다.
  bool renameCustomField(String from, String to) {
    final n = to.trim();
    if (n.isEmpty || n == from) return false;
    if (event.customFields.contains(n)) return false;
    if (builtinFieldLabels.values.contains(n)) return false;
    final i = event.customFields.indexOf(from);
    if (i < 0) return false;
    event.customFields[i] = n;
    for (final a in event.attendees) {
      final v = a.extra.remove(from);
      if (v != null) a.extra[n] = v;
    }
    commit();
    return true;
  }

  void addRoom(Room r) {
    event.rooms.add(r);
    commit();
  }

  /// "301-310" 또는 "301" 범위 문자열을 [building] 건물의 방으로 일괄 생성.
  /// 같은 건물에 이미 있는 호수는 건너뛴다 (건물이 다르면 같은 호수도 만든다).
  /// 반환값: (생성 수, 건너뛴 수)
  (int, int) addRoomRange(
    String range, {
    required int capacity,
    String? building,
    String? gender,
    String? note,
  }) {
    final b = (building ?? '').trim().isEmpty ? null : building!.trim();
    final existing = event.rooms.map((r) => r.label).toSet();
    var made = 0, skipped = 0;
    for (final n in parseRoomRange(range)) {
      final room = Room(
        id: newId(),
        roomNo: n,
        building: b,
        capacity: capacity,
        gender: gender,
        note: note,
      );
      if (!existing.add(room.label)) {
        skipped++;
        continue;
      }
      event.rooms.add(room);
      made++;
    }
    if (made > 0) commit();
    return (made, skipped);
  }

  /// 같은 건물·층 격자 안에서 [room] 을 [slot] 자리로 옮긴다.
  /// 그 자리에 다른 방이 있으면 서로 자리를 바꾼다.
  ///
  /// 옮기기 전에 지금 보이는 배치를 그대로 자리 번호로 굳힌다. 자동 배치된 방들은
  /// 앞자리가 비면 줄줄이 당겨지기 때문에, 굳히지 않으면 한 방을 옮길 때마다
  /// 옆방들이 같이 움직여 보인다.
  void moveRoom(Room room, int slot, {required int cols}) {
    if (slot < 0) return;
    final floor = layoutSlots(
      event.rooms.where((r) => r.floorGroup == room.floorGroup).toList(),
      cols,
    );
    for (var i = 0; i < floor.length; i++) {
      floor[i]?.slot = i;
    }
    final taken = slot < floor.length ? floor[slot] : null;
    if (taken == null || taken.id != room.id) {
      final from = room.slot;
      room.slot = slot;
      taken?.slot = from;
    }
    commit();
  }

  /// 손으로 옮긴 자리를 전부 지운다. 다시 호수 순 자동 배치로 돌아간다.
  void resetLayout() {
    for (final r in event.rooms) {
      r.slot = null;
    }
    commit();
  }

  /// 방 삭제. 배정된 인원은 미배정으로 되돌린다.
  int deleteRoom(Room room) {
    final freed = occupantsOf(room);
    for (final a in freed) {
      a.roomId = null;
    }
    event.rooms.removeWhere((r) => r.id == room.id);
    commit();
    return freed.length;
  }

  void assignAll(Iterable<Attendee> people, String? roomId) {
    for (final a in people) {
      a.roomId = roomId;
    }
    commit();
  }

  void setStay(Iterable<Attendee> people, DateTime checkIn, DateTime checkOut) {
    for (final a in people) {
      a.checkIn = checkIn;
      a.checkOut = checkOut;
      a.stayNights = null;
    }
    commit();
  }

  void deleteAttendees(Iterable<Attendee> people) {
    final ids = people.map((a) => a.id).toSet();
    // 신청에서 온 사람은 지웠다는 걸 기억한다. 안 그러면 다음 [신청에서 가져오기]에 말없이 되살아난다.
    event.deletedIds.addAll(
      people.where((a) => a.registrationId != null).map((a) => a.id),
    );
    event.attendees.removeWhere((a) => ids.contains(a.id));
    commit();
  }
}

/// 홈스테이 방 정원의 기본값. 신청서에 '수용 인원'을 안 적었거나 숫자가 아닐 때.
const defaultHomeCapacity = 4;

/// 홈스테이 신청서에 적힌 수용 인원. 신청자 본인 칸([Registration.people] 첫 사람)에서 읽는다.
int homeCapacityOf(Registration r) {
  final raw = r.people.firstOrNull?.extra[homestayCapacityField] ?? '';
  final n = int.tryParse(digitsOnly(raw));
  return n == null || n <= 0 ? defaultHomeCapacity : n;
}

/// "301-310", "301~310", "301" -> ["301","302",...]. 잘못된 입력은 빈 목록.
/// 쉼표로 여러 구간을 이어 붙일 수 있다: "101-105, 201".
List<String> parseRoomRange(String input) {
  final out = <String>[];
  for (final part in input.split(',')) {
    final s = part.trim();
    if (s.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*[-~]\s*(\d+)$').firstMatch(s);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      if (b < a || b - a > 999) continue; // 오타 방어
      for (var i = a; i <= b; i++) {
        out.add('$i');
      }
    } else if (RegExp(r'^\d+$').hasMatch(s)) {
      out.add(s);
    }
  }
  return out;
}

// --- CSV 내려받기 ----------------------------------------------------------

/// 참석자 목록 CSV (엑셀용, 줄바꿈 CRLF). 머리글은 붙여넣기 등록과 같은 이름이라
/// 엑셀에서 복사해 [붙여넣기 등록]으로 되돌려 넣을 수 있다.
String attendeesCsv(Event e) {
  final rooms = {for (final r in e.rooms) r.id: r.label};
  String cell(Object? v) {
    var s = '${v ?? ''}';
    // 신청 웹에서 들어온 값이 엑셀에서 수식으로 실행되지 않게 (CSV injection).
    if (RegExp(r'^[=+\-@\t\r]').hasMatch(s)) s = "'$s";
    return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return [
    [
      for (final k in defaultColumns) builtinFieldLabels[k]!,
      ...e.customFields,
      '방',
      '체크인',
      '체크아웃',
    ],
    for (final a in e.attendees)
      [
        a.name,
        switch (a.gender) {
          'M' => '남',
          'F' => '여',
          _ => '',
        },
        a.age == 0 ? '' : a.age,
        a.phone,
        a.cell,
        a.zone,
        a.note,
        for (final f in e.customFields) a.extra[f],
        rooms[a.roomId],
        ymd(a.checkIn),
        ymd(a.checkOut),
      ],
  ].map((row) => row.map(cell).join(',')).join('\r\n');
}

// --- 붙여넣기 파싱 ---------------------------------------------------------

/// 앱이 기본으로 갖고 있는 참석자 항목. 키 -> 화면에 보이는 이름.
const builtinFieldLabels = <String, String>{
  'name': '이름',
  'gender': '성별',
  'age': '나이',
  'phone': '전화',
  'cell': '셀',
  'zone': '존',
  'note': '기타',
};

/// 사용자 정의 항목의 컬럼 키는 이 접두사를 붙인다. (기본 항목 키와 안 겹치게)
const customFieldPrefix = 'x:';

/// 사용자 정의 항목 이름 -> 컬럼 키.
String customFieldKey(String name) => '$customFieldPrefix$name';

/// 컬럼 키가 사용자 정의 항목이면 그 이름, 아니면 null.
String? customFieldName(String key) => key.startsWith(customFieldPrefix)
    ? key.substring(customFieldPrefix.length)
    : null;

/// 붙여넣기 컬럼으로 지정 가능한 항목 전체 (기본 + 이 집회의 사용자 정의).
Map<String, String> attendeeColumnOptions(Event event) => {
  ...builtinFieldLabels,
  for (final f in event.customFields) customFieldKey(f): f,
  'skip': '(무시)',
};

const defaultColumns = [
  'name',
  'gender',
  'age',
  'phone',
  'cell',
  'zone',
  'note',
];

/// 파싱된 한 행. [attendee] 가 null 이면 [error] 에 이유가 들어있다.
class ParsedRow {
  ParsedRow(this.lineNo, this.cells, {this.attendee, this.error});
  final int lineNo;
  final List<String> cells;
  final Attendee? attendee;
  final String? error;
  bool get ok => attendee != null;
}

/// '남','남자','M','m','1' -> 'M' / '여','여자','F','f','2' -> 'F' / 그 외 null
String? normalizeGender(String raw) {
  final s = raw.trim().toLowerCase();
  if (['남', '남자', 'm', 'male', '1'].contains(s)) return 'M';
  if (['여', '여자', 'f', 'female', '2'].contains(s)) return 'F';
  return null;
}

/// 엑셀에서 복사한 TSV(탭 구분) 텍스트를 참석자로 파싱한다.
/// 탭이 없는 줄은 쉼표로도 나눠본다. 헤더로 보이는 첫 줄은 건너뛴다.
/// 나이 칸에 출생연도(4자리)가 오면 [checkIn] 연도 기준 연 나이로 바꾼다.
/// [requirePhone] = 신청으로 넣을 때. 서버가 휴대폰번호로 신청을 구분해서 꼭 있어야 한다.
List<ParsedRow> parseAttendeeText(
  String text, {
  required List<String> columns,
  required DateTime checkIn,
  required DateTime checkOut,
  required String Function() newId,
  bool requirePhone = false,
}) {
  final rows = <ParsedRow>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll('\r', '');
    if (line.trim().isEmpty) continue;
    final cells = (line.contains('\t') ? line.split('\t') : line.split(','))
        .map((c) => c.trim())
        .toList();

    // 헤더 행 건너뛰기
    if (rows.isEmpty &&
        cells.any((c) => c == '이름' || c.toLowerCase() == 'name')) {
      continue;
    }

    String? at(String field) {
      final idx = columns.indexOf(field);
      if (idx < 0 || idx >= cells.length) return null;
      final v = cells[idx].trim();
      return v.isEmpty ? null : v;
    }

    final name = at('name');
    final genderRaw = at('gender');
    final ageRaw = at('age');
    final gender = genderRaw == null ? null : normalizeGender(genderRaw);
    var age = ageRaw == null ? null : int.tryParse(ageRaw);
    if (age != null && age >= 1900) age = checkIn.year - age;
    final phone = at('phone');

    final problems = [
      if (name == null) '이름 없음',
      if (genderRaw == null)
        '성별 없음'
      else if (gender == null)
        '성별 인식 불가($genderRaw)',
      if (ageRaw == null)
        '나이 없음'
      else if (age == null || age < 0 || age > 130)
        '나이 오류($ageRaw)',
      if (requirePhone)
        if (phone == null)
          '전화 없음'
        else if (!validPhone(phone))
          '전화 오류($phone)',
    ];
    if (problems.isNotEmpty) {
      rows.add(ParsedRow(i + 1, cells, error: problems.join(', ')));
      continue;
    }

    // 사용자 정의 항목 값 모으기 (빈 값은 담지 않는다)
    final extra = <String, String>{};
    for (final col in columns) {
      final fieldName = customFieldName(col);
      if (fieldName == null) continue;
      final v = at(col);
      if (v != null) extra[fieldName] = v;
    }

    rows.add(
      ParsedRow(
        i + 1,
        cells,
        attendee: Attendee(
          id: newId(),
          name: name!,
          gender: gender!,
          age: age!,
          phone: phone,
          cell: at('cell'),
          zone: at('zone'),
          note: at('note'),
          checkIn: checkIn,
          checkOut: checkOut,
          extra: extra,
        ),
      ),
    );
  }
  return rows;
}
