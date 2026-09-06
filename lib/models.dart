/// 데이터 모델. JSON 파일 1개에 통째로 직렬화된다.
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
  );
}

class Room {
  String id;
  String roomNo;
  int capacity;
  String? gender; // 'M' | 'F' | null(무관)
  String? note;

  Room({
    required this.id,
    required this.roomNo,
    required this.capacity,
    this.gender,
    this.note,
  });

  /// "301" -> 3. 숫자가 아니면 null.
  int? get floor {
    final n = int.tryParse(roomNo.trim());
    return n == null ? null : n ~/ 100;
  }

  int? get roomNumber => int.tryParse(roomNo.trim());

  Map<String, dynamic> toJson() => {
    'id': id,
    'roomNo': roomNo,
    'capacity': capacity,
    'gender': gender,
    'note': note,
  };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'] as String,
    roomNo: j['roomNo'] as String,
    capacity: (j['capacity'] as num).toInt(),
    gender: j['gender'] as String?,
    note: j['note'] as String?,
  );
}

class Attendee {
  String id;
  String name;
  String gender; // 'M' | 'F'
  int age;
  String? phone, cell, zone, note;
  String? roomId;
  DateTime checkIn;
  DateTime checkOut;

  /// 사용자 정의 항목 값. 키는 [Event.customFields] 의 이름. 빈 값은 담지 않는다.
  Map<String, String> extra;

  Attendee({
    required this.id,
    required this.name,
    required this.gender,
    required this.age,
    this.phone,
    this.cell,
    this.zone,
    this.note,
    this.roomId,
    required this.checkIn,
    required this.checkOut,
    Map<String, String>? extra,
  }) : extra = extra ?? {};

  /// 하룻밤 [night] 에 이 방에 묵는가.
  bool staysOn(DateTime night) =>
      !night.isBefore(dateOnly(checkIn)) && night.isBefore(dateOnly(checkOut));

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
    'extra': extra,
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
    extra: (j['extra'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
  );
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 호수 오름차순. 숫자가 아닌 호수는 문자열로 비교한다.
/// 화면과 배정 엔진이 같은 순서를 봐야 해서 모델 쪽에 둔다.
int byRoomNo(Room a, Room b) {
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
