import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'gathering.dart';
import 'models.dart';

/// 앱 전체 상태. 집회 하나의 방배정 파일(JSON 1개)을 통째로 읽고 쓴다.
/// ponytail: 저장은 매 변경마다 전체 파일 재작성. 참석자 수천 명까지는 무의미하게 빠름.
class Store extends ChangeNotifier {
  Store({this.fileOverride});

  /// 테스트에서 임시 파일을 주입하기 위한 훅.
  final File? fileOverride;

  /// 열어 둔 집회 id. 파일은 `events/<id>.json`. null 이면 예전 버전의 `event.json`.
  String? gatheringId;

  Event event = Event(
    name: '새 집회',
    startDate: dateOnly(DateTime.now()),
    endDate: dateOnly(DateTime.now()).add(const Duration(days: 3)),
  );

  bool loaded = false;
  File? _file;

  Future<File> _resolveFile() async {
    if (fileOverride != null) return fileOverride!;
    final dir = await getApplicationSupportDirectory();
    return gatheringId == null
        ? File('${dir.path}/event.json')
        : File('${dir.path}/events/$gatheringId.json');
  }

  /// 집회 하나의 방배정 파일을 연다. 파일이 없으면 [fallback] 으로 시작한다.
  Future<void> open(String gatheringId, Event fallback) async {
    await _writes;
    this.gatheringId = gatheringId;
    _file = null;
    event = fallback;
    loadError = null;
    saveError = null;
    loaded = false;
    await load();
  }

  /// 이 PC 에 방배정 파일이 있는 집회들 (집회 id → 파일 속 Event).
  /// 서버에 못 붙을 때 집회 목록 대신 쓴다.
  static Future<Map<String, Event>> localEvents() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/events',
    );
    if (!await dir.exists()) return {};
    final out = <String, Event>{};
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is! File || !name.endsWith('.json')) continue;
      try {
        out[name.substring(0, name.length - 5)] = Event.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        // 깨진 파일은 목록에서만 뺀다. 열면 load() 가 .corrupt 로 치운다.
      }
    }
    return out;
  }

  /// 집회 목록이 생기기 전 버전의 방배정 파일 내용. 없거나 비었으면 null.
  static Future<Event?> legacyEvent() async {
    final f = File(
      '${(await getApplicationSupportDirectory()).path}/event.json',
    );
    try {
      if (!await f.exists()) return null;
      return Event.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// 예전 `event.json` 을 [gatheringId] 집회의 파일로 옮긴다.
  static Future<void> adoptLegacy(String gatheringId) async {
    final dir = (await getApplicationSupportDirectory()).path;
    await Directory('$dir/events').create(recursive: true);
    await File('$dir/event.json').rename('$dir/events/$gatheringId.json');
  }

  /// 파일이 깨져 있으면 옆으로 치우고 빈 집회로 시작한다.
  /// 여기서 예외가 나면 runApp 전에 죽어서 앱을 아예 못 켜게 된다.
  String? loadError;

  Future<void> load() async {
    _file = await _resolveFile();
    try {
      if (await _file!.exists()) {
        final text = await _file!.readAsString();
        if (text.trim().isNotEmpty) {
          event = Event.fromJson(jsonDecode(text) as Map<String, dynamic>);
        }
      }
    } catch (e) {
      final bak = '${_file!.path}.corrupt';
      try {
        await _file!.rename(bak);
      } catch (_) {}
      loadError = '저장 파일을 읽지 못해 새 집회로 시작합니다. 원본: $bak\n$e';
    }
    loaded = true;
    notifyListeners();
  }

  /// 임시 파일에 쓰고 rename. 도중에 죽어도 반쪽짜리 JSON 이 남지 않는다.
  Future<void> save() async {
    _file ??= await _resolveFile();
    await _file!.parent.create(recursive: true);
    final tmp = File('${_file!.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(event.toJson()),
      flush: true,
    );
    await tmp.rename(_file!.path);
  }

  /// 마지막 저장이 실패했으면 그 이유. UI 에서 보여줄 수 있다.
  String? saveError;
  Future<void> _writes = Future.value();

  /// 변경 후 저장 + 알림. UI는 이것만 부르면 된다.
  /// 저장은 순서대로 하나씩 — 두 개가 겹치면 파일이 반쯤 덮여 쓰인다.
  void commit() {
    notifyListeners();
    _writes = _writes.then((_) => save()).catchError((Object e) {
      saveError = '$e';
      debugPrint('저장 실패: $e');
    });
  }

  /// 테스트/종료 시 저장이 끝날 때까지 기다린다.
  Future<void> get pendingWrites => _writes;

  // --- 집회 설정 · 신청 → 방배정 ---

  /// 집회 설정(서버)을 이 PC 의 방배정 파일에 반영한다. 방배정 쪽 코드는 [Event] 만 본다.
  void applyGathering(Gathering g) {
    final s = dateOnly(g.start), e = dateOnly(g.end);
    event.name = g.name;
    event.startDate = s;
    event.endDate = e.isAfter(s) ? e : s.add(const Duration(days: 1));
    _addFields(g.formFields);
    commit();
  }

  /// 확정된 신청의 사람들 (사람 id → 참석자). 당일(0박) 참석자는 방이 필요 없어 뺀다.
  Map<String, Attendee> _wanted(Gathering g, List<Registration> regs) => {
    for (final r in regs)
      if (r.status == RegStatus.confirmed)
        for (final line in g.quoteFor(r.people, r.createdAt).lines)
          if (line.nights > 0) line.person.id: _attendeeOf(g, r, line.person),
  };

  Attendee _attendeeOf(Gathering g, Registration r, Person p) {
    final s = dateOnly(g.start), e = dateOnly(g.end);
    DateTime clamp(DateTime d) {
      final x = dateOnly(d);
      return x.isBefore(s) ? s : (x.isAfter(e) ? e : x);
    }

    return Attendee(
      id: p.id,
      name: p.name,
      gender: p.gender,
      age: g.start.year - p.birthYear,
      phone: fmtPhone(p.phone ?? r.phone),
      cell: p.cell,
      zone: p.zone,
      checkIn: clamp(p.checkIn ?? s),
      checkOut: clamp(p.checkOut ?? e),
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

  /// 확정된 신청을 참석자로 맞춘다. 몇 번 불러도 결과가 같다 (사람 id 로 맞춘다).
  ///
  /// - 신청에서 온 항목(이름·성별·나이·전화·셀·존·사용자 항목·일정)만 덮어쓰고
  ///   배정된 방(roomId)·기타(note)는 그대로 둔다.
  /// - 신청에서 왔는데 이제 확정 목록에 없는 사람(취소·되돌림·동반자 삭제)은 지운다.
  /// - 붙여넣기·직접 추가한 사람(registrationId == null)은 건드리지 않는다.
  ({int added, int updated, int removed, int dayOnly}) syncRegistrations(
    Gathering g,
    List<Registration> regs,
  ) {
    final want = _wanted(g, regs);
    final confirmedPeople = regs
        .where((r) => r.status == RegStatus.confirmed)
        .fold(0, (s, r) => s + r.people.length);
    final have = {for (final a in event.attendees) a.id: a};
    var added = 0, updated = 0;
    for (final w in want.values) {
      final a = have[w.id];
      if (a == null) {
        event.attendees.add(w);
        added++;
      } else if (!_sameSource(a, w)) {
        a
          ..name = w.name
          ..gender = w.gender
          ..age = w.age
          ..phone = w.phone
          ..cell = w.cell
          ..zone = w.zone
          ..checkIn = w.checkIn
          ..checkOut = w.checkOut
          ..extra = w.extra
          ..registrationId = w.registrationId;
        updated++;
      }
    }
    final before = event.attendees.length;
    event.attendees.removeWhere(
      (a) => a.registrationId != null && !want.containsKey(a.id),
    );
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

  bool _sameSource(Attendee a, Attendee b) =>
      a.name == b.name &&
      a.gender == b.gender &&
      a.age == b.age &&
      a.phone == b.phone &&
      a.cell == b.cell &&
      a.zone == b.zone &&
      a.checkIn == b.checkIn &&
      a.checkOut == b.checkOut &&
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

  /// 이름/셀/존/전화 통합 검색.
  List<Attendee> search(String q) {
    final k = q.trim().toLowerCase();
    if (k.isEmpty) return [...event.attendees];
    return event.attendees.where((a) {
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

  /// "301-310" 또는 "301" 범위 문자열을 방으로 일괄 생성. 이미 있는 호수는 건너뜀.
  /// 반환값: (생성 수, 건너뛴 수)
  (int, int) addRoomRange(
    String range, {
    required int capacity,
    String? gender,
    String? note,
  }) {
    final nums = parseRoomRange(range);
    final existing = event.rooms.map((r) => r.roomNo).toSet();
    var made = 0, skipped = 0;
    for (final n in nums) {
      if (existing.contains(n)) {
        skipped++;
        continue;
      }
      event.rooms.add(
        Room(
          id: newId(),
          roomNo: n,
          capacity: capacity,
          gender: gender,
          note: note,
        ),
      );
      existing.add(n);
      made++;
    }
    if (made > 0) commit();
    return (made, skipped);
  }

  /// 같은 층 격자 안에서 [room] 을 [slot] 자리로 옮긴다.
  /// 그 자리에 다른 방이 있으면 서로 자리를 바꾼다.
  ///
  /// 옮기기 전에 지금 보이는 배치를 그대로 자리 번호로 굳힌다. 자동 배치된 방들은
  /// 앞자리가 비면 줄줄이 당겨지기 때문에, 굳히지 않으면 한 방을 옮길 때마다
  /// 옆방들이 같이 움직여 보인다.
  void moveRoom(Room room, int slot, {required int cols}) {
    if (slot < 0) return;
    final floor = layoutSlots(
      event.rooms.where((r) => r.floor == room.floor).toList(),
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
    }
    commit();
  }

  void deleteAttendees(Iterable<Attendee> people) {
    final ids = people.map((a) => a.id).toSet();
    event.attendees.removeWhere((a) => ids.contains(a.id));
    commit();
  }
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
List<ParsedRow> parseAttendeeText(
  String text, {
  required List<String> columns,
  required DateTime checkIn,
  required DateTime checkOut,
  required String Function() newId,
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
    final age = ageRaw == null ? null : int.tryParse(ageRaw);

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
          phone: at('phone'),
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
