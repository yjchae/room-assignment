import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 앱 전체 상태. JSON 파일 1개를 통째로 읽고 쓴다.
/// ponytail: 저장은 매 변경마다 전체 파일 재작성. 참석자 수천 명까지는 무의미하게 빠름.
class Store extends ChangeNotifier {
  Store({this.fileOverride});

  /// 테스트에서 임시 파일을 주입하기 위한 훅.
  final File? fileOverride;

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
    return File('${dir.path}/event.json');
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
      ].any((f) => (f ?? '').toLowerCase().contains(k));
    }).toList();
  }

  // --- 변경 ---
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

/// 붙여넣기 컬럼으로 지정 가능한 필드.
const attendeeFields = <String, String>{
  'name': '이름',
  'gender': '성별',
  'age': '나이',
  'phone': '전화',
  'cell': '셀',
  'zone': '존',
  'note': '기타',
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
        ),
      ),
    );
  }
  return rows;
}
