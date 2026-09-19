/// 방배정 데이터 모델. 집회 하나의 [Event] 가 JSON 문서 하나로 통째로 직렬화돼
/// 서버 `room_plans` 에 저장된다 (store.dart).
library;

class Event {
  String name;
  DateTime startDate;
  DateTime endDate;
  List<Room> rooms;
  List<Attendee> attendees;

  /// 운영자가 직접 만든 참석자 항목 이름들 (예: '교회', '직분'). 순서 = 입력 화면 순서.
  /// 값은 [Attendee.extra] 에 같은 이름을 키로 들어간다.
  List<String> customFields;

  /// 운영자가 지운, 신청에서 온 참석자 id. 다시 가져올 때 되살릴지 묻는 데 쓴다.
  Set<String> deletedIds = {};

  Event({
    required this.name,
    required this.startDate,
    required this.endDate,
    List<Room>? rooms,
    List<Attendee>? attendees,
    List<String>? customFields,
  }) : rooms = rooms ?? [],
       attendees = attendees ?? [],
       customFields = customFields ?? [];

  /// 숙박 밤 목록: startDate ~ endDate-1일. 정원 계산의 기준.
  /// 기간이 0일 이하로 저장돼 있어도(손으로 고친 JSON 등) 최소 1박은 돌려준다.
  /// 빈 목록을 돌려주면 정원 검사가 통째로 무력화되기 때문.
  List<DateTime> get nights {
    final out = <DateTime>[];
    for (
      var d = dateOnly(startDate);
      d.isBefore(dateOnly(endDate));
      d = d.add(const Duration(days: 1))
    ) {
      out.add(d);
    }
    return out.isEmpty ? [dateOnly(startDate)] : out;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'rooms': rooms.map((r) => r.toJson()).toList(),
    'attendees': attendees.map((a) => a.toJson()).toList(),
    'customFields': customFields,
    'deletedIds': deletedIds.toList(),
  };

  factory Event.fromJson(Map<String, dynamic> j) => Event(
    name: j['name'] as String? ?? '',
    startDate: DateTime.parse(j['startDate'] as String),
    endDate: DateTime.parse(j['endDate'] as String),
    rooms: (j['rooms'] as List? ?? [])
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList(),
    attendees: (j['attendees'] as List? ?? [])
        .map((e) => Attendee.fromJson(e as Map<String, dynamic>))
        .toList(),
    customFields: (j['customFields'] as List? ?? []).map((e) => '$e').toList(),
  )..deletedIds = {for (final e in j['deletedIds'] as List? ?? []) '$e'};
}

/// 보드에서 같이 묶이는 단위 = 건물 + 층. 방 자리(slot)도 이 단위마다 따로 매긴다.
typedef FloorGroup = ({String? building, int? floor});

class Room {
  String id;
  String roomNo;

  /// 건물(동) 이름. 예: '반석관'. null = 건물 구분 없음.
  /// 건물이 다르면 같은 호수가 따로 있을 수 있고, 보드에서도 건물·층별로 따로 묶인다.
  String? building;
  int capacity;
  String? gender; // 'M' | 'F' | null(무관)
  String? note;

  /// 보드에서 이 방이 놓인 자리. 같은 층 격자의 0부터 세는 칸 번호.
  /// null 이면 호수 순서대로 자동 배치된다. 운영자가 드래그로 옮기면 값이 박힌다.
  int? slot;

  /// 홈스테이에서 이 방(가정)을 만든 신청 id. null = 운영자가 손으로 만든 방.
  /// 신청 조회에 "우리 집에 배정된 사람"을 돌려줄 때 이 값으로 찾는다 (schema.sql `_assigned`).
  String? registrationId;

  /// 홈스테이에서 이 가정이 신청서에 적은 "받을 수 있는 기간". null = 집회 전체.
  /// 배정할 때 이 기간을 보여 주고 며칠을 넣을지 고른다.
  DateTime? hostFrom, hostTo;

  Room({
    required this.id,
    required this.roomNo,
    this.building,
    required this.capacity,
    this.gender,
    this.note,
    this.slot,
    this.registrationId,
    this.hostFrom,
    this.hostTo,
  });

  /// "301" -> 3. 숫자가 아니면 null.
  int? get floor {
    final n = int.tryParse(roomNo.trim());
    return n == null ? null : n ~/ 100;
  }

  int? get roomNumber => int.tryParse(roomNo.trim());

  /// 화면에 보이는 이름. "반석관 101" / "101"
  String get label => building == null ? roomNo : '$building $roomNo';

  FloorGroup get floorGroup => (building: building, floor: floor);

  Map<String, dynamic> toJson() => {
    'id': id,
    'roomNo': roomNo,
    'building': building,
    'capacity': capacity,
    'gender': gender,
    'note': note,
    'slot': slot,
    if (registrationId != null) 'registrationId': registrationId,
    if (hostFrom != null) 'hostFrom': hostFrom!.toIso8601String(),
    if (hostTo != null) 'hostTo': hostTo!.toIso8601String(),
  };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'] as String,
    roomNo: j['roomNo'] as String,
    building: j['building'] as String?,
    capacity: (j['capacity'] as num).toInt(),
    gender: j['gender'] as String?,
    note: j['note'] as String?,
    slot: (j['slot'] as num?)?.toInt(),
    registrationId: j['registrationId'] as String?,
    hostFrom: j['hostFrom'] == null
        ? null
        : dateOnly(DateTime.parse('${j['hostFrom']}')),
    hostTo: j['hostTo'] == null
        ? null
        : dateOnly(DateTime.parse('${j['hostTo']}')),
  );
}

class Attendee {
  String id;
  String name;
  String gender; // 'M' | 'F'
  int age;
  String? phone, cell, note;

  /// 존. 'a존'·'A존'이 따로 세지 않게 항상 대문자로 담는다 (붙여넣기·수정·신청 가져오기 모두).
  String? get zone => _zone;
  set zone(String? v) => _zone = v?.toUpperCase();
  String? _zone;
  String? roomId;
  DateTime checkIn;
  DateTime checkOut;

  /// 신청에서 날짜를 띄엄띄엄 골라 중간에 빠진 밤이 있을 때만: 묵는 밤들.
  /// 있으면 [checkIn]~[checkOut] 대신 이것으로 정원을 센다. 운영자가 일정을 고치면 지운다.
  List<DateTime>? stayNights;

  /// 사용자 정의 항목 값. 키는 [Event.customFields] 의 이름. 빈 값은 담지 않는다.
  Map<String, String> extra;

  /// 신청에서 가져온 사람이면 그 신청 id. 같은 값 = 같은 가족(자동배정 '가족' 기준).
  /// null = 붙여넣기·직접 추가한 사람.
  String? registrationId;

  /// 운영자가 참석자 화면에서 직접 고쳤다. 신청에서 다시 가져올 때 덮어쓸지 묻는 데 쓴다.
  bool editedByAdmin = false;

  /// 기간을 나눠 다른 방(홈스테이는 다른 집)에 묵는 같은 사람이면 원래 참석자 id.
  /// null = 안 나눈 사람. 나뉜 조각은 저마다 일정·방을 따로 갖고, 정원도 제 기간만 차지한다.
  String? splitOf;

  /// 같은 사람을 묶는 id. 나뉜 조각들은 이 값이 같다 (화면에서 한 줄로 합쳐 보여준다).
  String get personId => splitOf ?? id;

  Attendee({
    required this.id,
    required this.name,
    required this.gender,
    required this.age,
    this.phone,
    this.cell,
    String? zone,
    this.note,
    this.roomId,
    required this.checkIn,
    required this.checkOut,
    this.stayNights,
    Map<String, String>? extra,
    this.registrationId,
  }) : extra = extra ?? {},
       _zone = zone?.toUpperCase();

  /// 하룻밤 [night] 에 이 방에 묵는가.
  bool staysOn(DateTime night) =>
      stayNights?.contains(dateOnly(night)) ??
      (!night.isBefore(dateOnly(checkIn)) &&
          night.isBefore(dateOnly(checkOut)));

  /// 하루 [day] 에 집회에 와 있는가: 그날 밤 묵거나, 전날 밤 묵고 그날 떠난다.
  /// 일정이 집회 밤([nights])과 하나도 안 겹치는 사람(집회 날짜를 정하기 전에 넣은 사람 등)은
  /// [stayMask] 와 같이 모든 날 온 것으로 본다 — 안 그러면 전체에는 있는데 어느 날에도 안 잡힌다.
  /// ponytail: 참석자는 묵는 밤만 들고 있어서 1박 이상인 사람의 따로 떨어진 당일 방문
  /// (1·2·4일 신청의 4일)은 빠진다. 정확히 보려면 신청의 Person.days 를 참석자에 담는다.
  bool attendsOn(DateTime day, List<DateTime> nights) =>
      !nights.any(staysOn) ||
      staysOn(day) ||
      staysOn(DateTime(day.year, day.month, day.day - 1));

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gender': gender,
    'age': age,
    'phone': phone,
    'cell': cell,
    'zone': zone,
    'note': note,
    'roomId': roomId,
    'checkIn': checkIn.toIso8601String(),
    'checkOut': checkOut.toIso8601String(),
    if (stayNights != null)
      'stayNights': [for (final d in stayNights!) d.toIso8601String()],
    'extra': extra,
    'registrationId': registrationId,
    if (editedByAdmin) 'edited': true,
    if (splitOf != null) 'splitOf': splitOf,
  };

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
    id: j['id'] as String,
    name: j['name'] as String,
    gender: j['gender'] as String,
    age: (j['age'] as num).toInt(),
    phone: j['phone'] as String?,
    cell: j['cell'] as String?,
    zone: j['zone'] as String?,
    note: j['note'] as String?,
    roomId: j['roomId'] as String?,
    checkIn: DateTime.parse(j['checkIn'] as String),
    checkOut: DateTime.parse(j['checkOut'] as String),
    stayNights: (j['stayNights'] as List?)
        ?.map((e) => dateOnly(DateTime.parse('$e')))
        .toList(),
    extra: (j['extra'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
    registrationId: j['registrationId'] as String?,
  )
    ..editedByAdmin = j['edited'] == true
    ..splitOf = j['splitOf'] as String?;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 과거 집회의 방배정에서 [rooms]·[attendees] 를 골라 새 집회([start]~[end])용으로 옮긴다.
/// 참석자는 방 배정·일정·신청 연결을 푼다 (새 집회엔 그 신청이 없어 [신청에서 가져오기] 때
/// 지워지면 안 된다). 나이는 해가 바뀐 만큼 더한다. 원본은 건드리지 않는다.
Event copyEvent(
  Event src, {
  required String name,
  required DateTime start,
  required DateTime end,
  bool rooms = false,
  bool attendees = false,
}) {
  final years = start.year - src.startDate.year;
  final e = Event(
    name: name,
    startDate: dateOnly(start),
    endDate: dateOnly(end),
    customFields: attendees ? [...src.customFields] : [],
  );
  if (rooms) {
    e.rooms = [
      // 신청 연결은 푼다 — 새 집회엔 그 신청이 없다 (참석자의 registrationId 와 같은 이유).
      for (final r in src.rooms)
        Room.fromJson({
          ...r.toJson(),
          'registrationId': null,
          'hostFrom': null,
          'hostTo': null,
        }),
    ];
  }
  if (attendees) {
    e.attendees = [
      for (final a in src.attendees)
        Attendee.fromJson({
          ...a.toJson(),
          'roomId': null,
          'registrationId': null,
          'edited': false,
          'age': a.age == 0 ? 0 : a.age + years, // 0 = 모름
          'checkIn': e.startDate.toIso8601String(),
          'checkOut': e.endDate.toIso8601String(),
          'splitOf': null,
        })..stayNights = null,
    ];
  }
  return e;
}

/// 건물 이름 순(건물 없는 방이 먼저) → 호수 오름차순. 숫자가 아닌 호수는 문자열로 비교한다.
/// 화면과 배정 엔진이 같은 순서를 봐야 해서 모델 쪽에 둔다.
int byRoomNo(Room a, Room b) {
  final bd = (a.building ?? '').compareTo(b.building ?? '');
  if (bd != 0) return bd;
  final x = a.roomNumber, y = b.roomNumber;
  if (x != null && y != null) return x.compareTo(y);
  if (x != null) return -1;
  if (y != null) return 1;
  return a.roomNo.compareTo(b.roomNo);
}

/// 방의 밤별 인원수. 정원 계산은 전부 이 함수 하나를 거친다.
///
/// 일정이 [nights] 와 하나도 겹치지 않는 사람(체크인/아웃이 집회 기간 밖 = 데이터 오류)은
/// **모든 밤을 차지하는 것으로** 센다. 0으로 세면 그런 사람들은 정원을 아무리 넘겨도
/// 화면에 0/4 로 보여서 초과가 전혀 드러나지 않는다.
List<int> occupancyByNight(
  Iterable<Attendee> occupants,
  List<DateTime> nights,
) {
  final counts = List<int>.filled(nights.length, 0);
  for (final a in occupants) {
    final stays = stayMask(a, nights);
    for (var i = 0; i < nights.length; i++) {
      if (stays[i]) counts[i]++;
    }
  }
  return counts;
}

/// [a] 가 각 밤에 방을 차지하는지. 하나도 안 겹치면 전부 차지로 본다.
List<bool> stayMask(Attendee a, List<DateTime> nights) {
  final m = [for (final n in nights) a.staysOn(n)];
  return m.contains(true) ? m : List<bool>.filled(nights.length, true);
}

/// 한 층의 방들을 격자 자리에 놓는다. 반환 길이는 항상 [cols] 의 배수라
/// 그대로 [cols] 개씩 끊으면 한 줄이 된다. null 인 칸은 빈 자리(복도·엘리베이터).
///
/// [Room.slot] 이 박혀 있는 방은 그 자리에, 나머지는 남은 앞자리부터 호수 순으로 채운다.
/// 같은 자리를 두 방이 주장하면 호수가 빠른 쪽이 갖고 다른 쪽은 자동 배치로 밀린다
/// (손으로 고친 JSON 이라도 방이 사라지지는 않게).
List<Room?> layoutSlots(List<Room> rooms, int cols) {
  final grid = <Room?>[];
  void grow(int len) {
    while (grid.length < len) {
      grid.add(null);
    }
  }

  final auto = <Room>[];
  for (final r in [...rooms]..sort(byRoomNo)) {
    final s = r.slot;
    if (s == null || s < 0 || s >= _slotLimit) {
      auto.add(r);
      continue;
    }
    grow(s + 1);
    if (grid[s] == null) {
      grid[s] = r;
    } else {
      auto.add(r);
    }
  }

  var cursor = 0;
  for (final r in auto) {
    while (cursor < grid.length && grid[cursor] != null) {
      cursor++;
    }
    grow(cursor + 1);
    grid[cursor] = r;
  }

  if (cols > 0 && grid.length % cols != 0) {
    grow(grid.length + cols - grid.length % cols);
  }
  return grid;
}

/// 자리 번호 상한. 이보다 큰 값은 오타나 깨진 파일로 보고 자동 배치로 되돌린다.
/// (자리 하나가 곧 위젯 하나라 상한이 없으면 격자가 통째로 커진다.)
const _slotLimit = 10000;
