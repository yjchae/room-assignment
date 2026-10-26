// 기간 나눈 사람 집계 · 미숙박 · 참석자 일정 → 신청서 반영.
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/store.dart';

final d1 = DateTime(2026, 10, 1), d4 = DateTime(2026, 10, 4); // 3박

/// 신청 목록과 고친 내용을 메모리에 둔다.
class RegRemote extends Remote {
  RegRemote(this.regs);
  final List<Registration> regs;
  final patches = <String, Map<String, dynamic>>{};

  @override
  Future<List<Registration>> registrations(String gatheringId) async => regs;

  @override
  Future<Registration> patchRegistration(
    String id,
    Map<String, dynamic> fields,
  ) async {
    patches[id] = fields;
    return regs.firstWhere((r) => r.id == id);
  }
}

Gathering gathering() => Gathering(
  id: 'g1',
  name: '수양회',
  start: d1,
  end: d4,
  fee: FeeRule(perNight: {AgeGroup.adult: 70000}),
);

void main() {
  test('기간을 나눠 두 방에 넣어도 사람 수·내려받기는 한 명', () {
    final s = Store()..event = Event(name: 'x', startDate: d1, endDate: d4);
    s.event.rooms.addAll([
      Room(id: 'A', roomNo: '101', capacity: 2),
      Room(id: 'B', roomNo: '102', capacity: 2),
    ]);
    final a = Attendee(
      id: 'p1',
      name: '홍',
      gender: 'M',
      age: 30,
      checkIn: d1,
      checkOut: d4,
      roomId: 'A',
    );
    s.event.attendees.add(a);
    s.splitStay(a, DateTime(2026, 10, 2))!.roomId = 'B';
    expect(s.event.attendees, hasLength(2));
    expect(onePerPerson(s.event.attendees), hasLength(1));
    final names = {for (final r in s.event.rooms) r.id: r.label};
    expect(roomLabelOf(names, s.partsOf(a)), '101 → 102');
    final rows = attendeeRows(s.event, s.event.attendees);
    expect(rows, hasLength(2)); // 머리글 + 한 사람
    expect(
      rows[1],
      containsAllInOrder(['101 → 102', '2026-10-01', '2026-10-04']),
    );
  });

  test('미숙박은 방 정원에 안 잡히고 미배정에서도 빠진다', () {
    final s = Store()..event = Event(name: 'x', startDate: d1, endDate: d4);
    final room = Room(id: 'A', roomNo: '101', capacity: 1);
    s.event.rooms.add(room);
    final a = Attendee(
      id: 'p1',
      name: '홍',
      gender: 'M',
      age: 30,
      checkIn: d1,
      checkOut: d4,
    );
    s.event.attendees.add(a);
    s.assignAll([a], noStayRoom);
    expect(a.noStay, isTrue);
    expect(s.unassigned, isEmpty);
    expect(s.peakOccupancy(room), 0);
    expect(roomLabelOf({'A': '101'}, [a]), '미숙박');
  });

  test('참석자 일정을 고치면 신청서 날짜가 바뀌고 계산 금액이 따라간다', () async {
    final p = Person(id: 'p1', name: '홍', gender: 'M', birthYear: 1980);
    final r = Registration(
      id: 'r1',
      gatheringId: 'g1',
      phone: '01012345678',
      people: [p],
      createdAt: DateTime(2026, 9, 1),
    );
    remote = RegRemote([r]);
    final g = gathering();
    expect(g.quoteFor(r.people, r.createdAt).beforeDiscount, 210000);
    final s = Store()..event = Event(name: 'x', startDate: d1, endDate: d4);
    s.syncRegistrations(g, [r]);
    final a = s.event.attendees.single;
    s.setStay([a], d1, DateTime(2026, 10, 3)); // 2박으로 줄임
    expect(await s.writeStayToRegistrations(g, [a]), 1);
    final sent = (remote as RegRemote).patches['r1']!;
    // 신청 때 금액(quoted)은 건드리지 않는다 — 금액 체크는 예전과 같다.
    expect(sent.containsKey('quoted'), isFalse);
    r.people = [
      for (final x in sent['people'] as List) Person.fromJson(x as Map),
    ];
    expect(g.quoteFor(r.people, r.createdAt).beforeDiscount, 140000);
    expect(
      Person.fromJson((sent['people'] as List).single as Map).daysIn(d1, d4),
      [d1, DateTime(2026, 10, 2), DateTime(2026, 10, 3)],
    );
    // 이제 신청과 참석자가 같아서 가져오기가 되돌리지 않는다.
    expect(s.syncRegistrations(g, [r]).updated, 0);
    expect(s.event.attendees.single.checkOut, DateTime(2026, 10, 3));
    // 같은 일정이면 다시 쓰지 않는다.
    expect(await s.writeStayToRegistrations(g, [a]), 0);
  });

  test('글자 호수는 받고, 숫자뿐인 오타는 방으로 만들지 않는다', () {
    final s = Store()..event = Event(name: 'x', startDate: d1, endDate: d4);
    expect(s.addRoomRange('A101, 301-302', capacity: 4, names: true), (3, 0));
    for (final typo in ['310-301', '101-1200', '301 302']) {
      expect(s.addRoomRange(typo, capacity: 4, names: true), (0, 0));
    }
    expect(s.event.rooms.map((r) => r.roomNo), ['A101', '301', '302']);
  });

  test('충돌 합치기: 지운 방에 넣은 사람은 미배정, 지운 기록은 양쪽 것을 합친다', () {
    Map<String, dynamic> doc(
      List<Room> rooms,
      List<Attendee> people,
      List<String> deleted,
    ) => (Event(
      name: 'x',
      startDate: d1,
      endDate: d4,
      rooms: rooms,
      attendees: people,
    )..deletedIds = deleted.toSet()).toJson();
    Attendee p(String id, [String? room]) => Attendee(
      id: id,
      name: id,
      gender: 'M',
      age: 30,
      checkIn: d1,
      checkOut: d4,
      roomId: room,
    );
    Room r(String id) => Room(id: id, roomNo: id, capacity: 4);
    final base = doc([r('A')], [p('kim')], []);
    // 내 쪽: kim 을 A 에 넣고 x 를 지웠다. 서버 쪽: A 방을 지우고 y 를 지웠다.
    final mine = doc([r('A')], [p('kim', 'A')], ['x']);
    final server = doc([], [p('kim')], ['y']);
    final e = Event.fromJson(mergePlan(base, mine, server));
    expect(e.rooms, isEmpty);
    expect(e.attendees.single.roomId, isNull);
    expect(e.deletedIds, {'x', 'y'});
  });

  test('일정을 줄여도 따로 신청한 당일 방문은 신청서에 남는다', () async {
    DateTime day(int d) => DateTime(2026, 10, d);
    final p = Person(
      id: 'p1',
      name: '홍',
      gender: 'M',
      birthYear: 1980,
      days: [day(1), day(2), day(4)], // 1박 + 4일 당일
    );
    final r = Registration(
      id: 'r1',
      gatheringId: 'g1',
      phone: '01012345678',
      people: [p],
      createdAt: DateTime(2026, 9, 1),
    );
    remote = RegRemote([r]);
    final g = gathering();
    final s = Store()..event = Event(name: 'x', startDate: d1, endDate: d4);
    s.syncRegistrations(g, [r]);
    final a = s.event.attendees.single;
    s.setStay([a], day(2), day(3)); // 1일 밤 → 2일 밤으로 옮김
    expect(await s.writeStayToRegistrations(g, [a]), 1);
    final sent = (remote as RegRemote).patches['r1']!;
    expect(
      Person.fromJson((sent['people'] as List).single as Map).daysIn(d1, d4),
      [day(2), day(3), day(4)],
    );
  });
}
