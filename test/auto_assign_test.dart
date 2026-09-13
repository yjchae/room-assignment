import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/auto_assign.dart';
import 'package:room_assignment/gathering.dart' show Gathering;
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/store.dart';

final d0 = DateTime(2026, 1, 1);
final d3 = DateTime(2026, 1, 4); // 3박

int _n = 0;
String nid() => 'id${_n++}';

/// 메모리 서버의 방배정 문서 하나. schema.sql save_room_plan 과 같은 버전 규칙.
class PlanRemote extends Remote {
  Map<String, dynamic>? data;
  int version = 0, saves = 0;

  Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Future<({Map<String, dynamic> data, int version})?> roomPlan(
    String gatheringId,
  ) async => data == null ? null : (data: _copy(data!), version: version);

  @override
  Future<int> saveRoomPlan(
    String gatheringId,
    Map<String, dynamic> d,
    int v,
  ) async {
    if (v != version) throw const RemoteError('CONFLICT');
    data = _copy(d);
    saves++;
    return ++version;
  }
}

Event ev({
  List<Room>? rooms,
  List<Attendee>? attendees,
  List<String>? customFields,
}) => Event(
  name: 't',
  startDate: d0,
  endDate: d3,
  rooms: rooms,
  attendees: attendees,
  customFields: customFields,
);

Room room(String no, int cap, {String? gender}) =>
    Room(id: 'r$no', roomNo: no, capacity: cap, gender: gender);

Attendee person(
  String name, {
  String gender = 'M',
  int age = 30,
  String? cell,
  String? zone,
  String? note,
  String? roomId,
  DateTime? checkIn,
  DateTime? checkOut,
}) => Attendee(
  id: nid(),
  name: name,
  gender: gender,
  age: age,
  cell: cell,
  zone: zone,
  note: note,
  roomId: roomId,
  checkIn: checkIn ?? d0,
  checkOut: checkOut ?? d3,
);

void main() {
  group('정원 계산', () {
    test('날짜가 겹치지 않으면 정원을 나눠 쓴다', () {
      final r = room('101', 1);
      final e = ev(
        rooms: [r],
        attendees: [
          person(
            'A',
            roomId: r.id,
            checkIn: d0,
            checkOut: DateTime(2026, 1, 2),
          ),
          person(
            'B',
            roomId: r.id,
            checkIn: DateTime(2026, 1, 2),
            checkOut: DateTime(2026, 1, 4),
          ),
        ],
      );
      final s = Store()..event = e;
      expect(s.peakOccupancy(r), 1); // 동시에 있지 않으므로 1
      expect(s.freeSeats(r), 0);
    });

    test('겹치면 합산된다', () {
      final r = room('101', 4);
      final e = ev(
        rooms: [r],
        attendees: [
          person('A', roomId: r.id),
          person('B', roomId: r.id),
        ],
      );
      expect((Store()..event = e).peakOccupancy(r), 2);
    });
  });

  group('호수 범위 파싱', () {
    test('범위와 단일, 쉼표 조합', () {
      expect(parseRoomRange('301-303'), ['301', '302', '303']);
      expect(parseRoomRange('301~302, 401'), ['301', '302', '401']);
      expect(parseRoomRange('abc'), isEmpty);
      expect(parseRoomRange('303-301'), isEmpty); // 역순은 무시
    });
  });

  group('붙여넣기 파싱', () {
    test('TSV 파싱 + 오류 행 표시', () {
      final rows = parseAttendeeText(
        '이름\t성별\t나이\n'
        '홍길동\t남\t34\n'
        '김영희\tF\t28\n'
        '오류\t중성\t30\n'
        '나이없음\t남\tabc\n',
        columns: defaultColumns,
        checkIn: d0,
        checkOut: d3,
        newId: nid,
      );
      expect(rows.length, 4); // 헤더 제외
      expect(rows.where((r) => r.ok).length, 2);
      expect(rows[0].attendee!.name, '홍길동');
      expect(rows[0].attendee!.gender, 'M');
      expect(rows[1].attendee!.gender, 'F');
      expect(rows[2].error, contains('성별'));
      expect(rows[3].error, contains('나이'));
    });

    test('탭이 없으면 쉼표로도 나눈다', () {
      final rows = parseAttendeeText(
        '홍길동,남,34',
        columns: defaultColumns,
        checkIn: d0,
        checkOut: d3,
        newId: nid,
      );
      expect(rows.single.attendee!.age, 34);
    });
  });

  group('자동배정', () {
    test('기존 배정은 건드리지 않고 미배정만 채운다', () {
      final r1 = room('101', 2);
      final r2 = room('102', 2);
      final fixed = person('고정', roomId: r1.id);
      final e = ev(rooms: [r1, r2], attendees: [fixed, person('신규')]);
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 1);
      expect(res.assignments.single.attendee.name, '신규');
      expect(fixed.roomId, r1.id);
    });

    test('우대 대상은 지정된 층에 먼저 들어간다', () {
      final rooms = [room('101', 1), room('201', 1), room('301', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [person('젊은이', age: 30), person('어르신', age: 70)],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: 65, floorMin: 1, floorMax: 1),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.firstWhere((a) => a.name == '어르신').roomId, 'r101');
      expect(
        e.attendees.firstWhere((a) => a.name == '젊은이').roomId,
        isNot('r101'),
      );
    });

    test('나이 많은 순으로 낮은 층부터', () {
      final rooms = [room('101', 1), room('201', 1)];
      final e = ev(
        rooms: rooms,
        attendees: [person('70세', age: 70), person('80세', age: 80)],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: 65, floorMin: 1, floorMax: 2),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.firstWhere((a) => a.name == '80세').roomId, 'r101');
      expect(e.attendees.firstWhere((a) => a.name == '70세').roomId, 'r201');
    });

    test('같은 셀은 가까운 호수로 모인다', () {
      final rooms = [room('101', 2), room('102', 2), room('501', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          for (var i = 0; i < 4; i++) person('셀원$i', zone: 'A', cell: '1셀'),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);
      final used = e.attendees.map((a) => a.roomId).toSet();
      expect(used, {'r101', 'r102'}); // 501호로 흩어지지 않음
    });

    test('성별 분리 ON이면 첫 배정자 성별로 방이 고정된다', () {
      final e = ev(
        rooms: [room('101', 4)],
        attendees: [
          person('남1'),
          person('여1', gender: 'F'),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 1);
      expect(res.unplaced.single.gender, 'F');
    });

    test('성별 지정된 방에는 맞는 성별만', () {
      final e = ev(
        rooms: [room('101', 4, gender: 'F')],
        attendees: [person('남1')],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments, isEmpty);
      expect(res.unplaced.length, 1);
    });

    test('성별 분리 OFF면 섞인다', () {
      final e = ev(
        rooms: [room('101', 4)],
        attendees: [
          person('남1'),
          person('여1', gender: 'F'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, separateGender: false),
      );
      expect(res.assignments.length, 2);
    });

    test('정원을 넘겨 배정하지 않는다', () {
      final e = ev(
        rooms: [room('101', 2)],
        attendees: [for (var i = 0; i < 5; i++) person('P$i')],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 2);
      expect(res.unplaced.length, 3);
    });

    test('날짜가 겹치지 않으면 같은 자리를 재사용한다', () {
      final e = ev(
        rooms: [room('101', 1)],
        attendees: [
          person('앞', checkIn: d0, checkOut: DateTime(2026, 1, 2)),
          person('뒤', checkIn: DateTime(2026, 1, 2), checkOut: d3),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 2);
      expect(res.unplaced, isEmpty);
    });

    test('기타사항 키워드로도 우대된다', () {
      final e = ev(
        rooms: [room('101', 1), room('301', 1)],
        attendees: [
          person('일반'),
          person('강사님', note: '강사'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(
          priorityAge: null,
          priorityKeyword: '강사',
          floorMin: 1,
          floorMax: 1,
        ),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.firstWhere((a) => a.name == '강사님').roomId, 'r101');
    });
  });

  group('리뷰에서 나온 정원 구멍', () {
    test('일정이 집회 기간 밖인 사람도 자리를 차지한다', () {
      final r = room('101', 2);
      final out = [
        for (var i = 0; i < 5; i++)
          person(
            'P$i',
            roomId: r.id,
            checkIn: DateTime(2026, 2, 1),
            checkOut: DateTime(2026, 2, 3),
          ),
      ];
      final s = Store()..event = ev(rooms: [r], attendees: out);
      expect(s.peakOccupancy(r), 5); // 예전엔 0 이라 초과가 안 보였다
      expect(s.freeSeats(r), lessThan(0));
    });

    test('기간 밖 인원을 자동배정이 무한정 넣지 않는다', () {
      final e = ev(
        rooms: [room('101', 2)],
        attendees: [
          for (var i = 0; i < 5; i++)
            person(
              'P$i',
              checkIn: DateTime(2026, 2, 1),
              checkOut: DateTime(2026, 2, 3),
            ),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 2);
      expect(res.unplaced.length, 3);
    });

    test('시작일=종료일이어도 정원을 지킨다', () {
      final e = Event(
        name: 't',
        startDate: d0,
        endDate: d0,
        rooms: [room('101', 1)],
        attendees: [person('A'), person('B')],
      );
      expect(e.nights.length, 1);
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.length, 1);
      expect(res.unplaced.length, 1);
    });

    test('어느 하룻밤만 만실인 방도 그룹 단계에서 후보로 남는다', () {
      // 101호는 첫날밤만 차 있다. 둘째밤부터 오는 같은 셀 사람은 여기 들어갈 수 있어야 한다.
      // (예전엔 '최대 동시인원 기준 남은 자리 > 0' 으로 걸러서 101호가 통째로 빠졌다)
      final e = ev(
        rooms: [room('101', 1), room('501', 1)],
        attendees: [
          person(
            '먼저',
            cell: 'c1',
            zone: 'A',
            roomId: 'r101',
            checkIn: d0,
            checkOut: DateTime(2026, 1, 2),
          ),
          person(
            '나중',
            cell: 'c1',
            zone: 'A',
            checkIn: DateTime(2026, 1, 2),
            checkOut: d3,
          ),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);
      expect(e.attendees.firstWhere((a) => a.name == '나중').roomId, 'r101');
    });

    test('존/셀이 없는 사람들은 한 덩어리 그룹으로 묶이지 않는다', () {
      final e = ev(
        rooms: [room('101', 4), room('102', 4)],
        attendees: [
          for (var i = 0; i < 3; i++) person('무소속\$i'),
          person('셀1', zone: 'A', cell: 'c1'),
          person('셀2', zone: 'A', cell: 'c1'),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);
      final cellRooms = e.attendees
          .where((a) => a.cell == 'c1')
          .map((a) => a.roomId)
          .toSet();
      expect(cellRooms.length, 1); // 같은 셀은 여전히 한 방
      expect(res.unplaced, isEmpty);
    });
  });

  group('그룹 기준 우선순위', () {
    test('기본값은 예전과 같다 (존, 셀)', () {
      expect(AutoRule().groupBy, [GroupField.zone, GroupField.cell]);
    });

    test('기준을 셀 하나로 두면 존이 달라도 같이 모인다', () {
      final rooms = [room('101', 2), room('501', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('A', zone: 'A존', cell: '1셀'),
          person('B', zone: 'B존', cell: '1셀'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.cell]),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.map((a) => a.roomId).toSet().length, 1);
    });

    test('존이 1순위면 셀이 달라도 존이 같은 방 옆에 붙는다', () {
      // 101 에 A존 사람이 이미 있다. 셀은 다르지만 존이 같은 신규는 101 로 가야 한다.
      final rooms = [room('101', 2), room('501', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('기존', zone: 'A존', cell: '1셀', roomId: 'r101'),
          person('신규', zone: 'A존', cell: '9셀'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(
          priorityAge: null,
          groupBy: [GroupField.zone, GroupField.cell],
        ),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.firstWhere((a) => a.name == '신규').roomId, 'r101');
    });

    test('순서를 뒤집으면 붙는 대상도 바뀐다', () {
      // 셀이 1순위: 101(1셀) 과 501(9셀) 중 같은 1셀 쪽에 붙는다.
      final rooms = [room('101', 2), room('501', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('존만같음', zone: 'A존', cell: '9셀', roomId: 'r101'),
          person('셀만같음', zone: 'B존', cell: '1셀', roomId: 'r501'),
          person('신규', zone: 'A존', cell: '1셀'),
        ],
      );

      GroupField? roomOf(List<GroupField> order) {
        for (final a in e.attendees) {
          if (a.name == '신규') a.roomId = null;
        }
        final res = autoAssign(e, AutoRule(priorityAge: null, groupBy: order));
        applyAssignments(res.assignments);
        final id = e.attendees.firstWhere((a) => a.name == '신규').roomId;
        return id == 'r101' ? GroupField.zone : GroupField.cell;
      }

      expect(roomOf([GroupField.zone, GroupField.cell]), GroupField.zone);
      expect(roomOf([GroupField.cell, GroupField.zone]), GroupField.cell);
    });

    test('기준이 비어 있으면 그룹 없이 빈자리부터 채운다', () {
      final e = ev(
        rooms: [room('101', 4)],
        attendees: [
          person('A', zone: 'A존', cell: '1셀'),
          person('B', zone: 'B존', cell: '2셀'),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null, groupBy: []));
      expect(res.assignments.length, 2);
      expect(res.assignments.every((x) => x.stage == '잔여'), isTrue);
    });

    test('기준 값이 비어 있는 사람은 그룹으로 묶이지 않는다', () {
      final e = ev(
        rooms: [room('101', 4)],
        attendees: [person('무소속'), person('무소속2')],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      expect(res.assignments.every((x) => x.stage == '잔여'), isTrue);
    });

    test('기타(note)도 기준으로 쓸 수 있다', () {
      final rooms = [room('101', 2), room('501', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('A', note: '한빛교회'),
          person('B', note: '한빛교회'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.note]),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.map((a) => a.roomId).toSet().length, 1);
    });
  });

  group('단체를 여러 방에 배정 (distribute)', () {
    test('호수 순으로 정원만큼 채운다', () {
      final rooms = [room('301', 2), room('302', 2), room('303', 2)];
      final people = [
        for (var i = 0; i < 6; i++) person('셀원$i', cell: '에클레시아'),
      ];
      final e = ev(rooms: rooms, attendees: people);
      final r = distribute(e, people, rooms);
      applyAssignments(r.assignments);
      expect(r.unplaced, isEmpty);
      expect(people.map((a) => a.roomId).toList(), [
        'r301',
        'r301',
        'r302',
        'r302',
        'r303',
        'r303',
      ]);
    });

    test('자리가 모자라면 남는 사람을 돌려준다', () {
      final rooms = [room('301', 2)];
      final people = [for (var i = 0; i < 5; i++) person('P$i')];
      final e = ev(rooms: rooms, attendees: people);
      final r = distribute(e, people, rooms);
      expect(r.assignments.length, 2);
      expect(r.unplaced.length, 3);
    });

    test('overflow: true 면 전원 배정하되 정원을 넘긴다', () {
      final rooms = [room('301', 2), room('302', 2)];
      final people = [for (var i = 0; i < 6; i++) person('P$i')];
      final e = ev(rooms: rooms, attendees: people);
      final r = distribute(e, people, rooms, overflow: true);
      applyAssignments(r.assignments);
      expect(r.unplaced, isEmpty);
      expect(r.assignments.length, 6);
      final s = Store()..event = e;
      expect(s.peakOccupancy(rooms[0]), 3); // 초과가 눈에 보여야 한다
      expect(s.peakOccupancy(rooms[1]), 3);
    });

    test('이미 그 방에 있던 사람을 두 번 세지 않는다', () {
      final rooms = [room('301', 2)];
      final already = person('기존', roomId: 'r301');
      final e = ev(rooms: rooms, attendees: [already, person('신규')]);
      // 기존 인원을 포함해 다시 배정 → 2명이므로 정확히 들어가야 한다
      final r = distribute(e, e.attendees, rooms);
      expect(r.unplaced, isEmpty);
      expect(r.assignments.length, 2);
    });

    test('다른 방에 있던 기존 인원의 자리는 그대로 센다', () {
      final rooms = [room('301', 2)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('붙박이', roomId: 'r301'),
          person('A'),
          person('B'),
        ],
      );
      final movers = e.attendees.where((a) => a.name != '붙박이').toList();
      final r = distribute(e, movers, rooms);
      expect(r.assignments.length, 1); // 남은 자리 1개
      expect(r.unplaced.length, 1);
    });

    test('날짜가 겹치지 않으면 같은 자리를 재사용한다', () {
      final rooms = [room('301', 1)];
      final people = [
        person('앞', checkIn: d0, checkOut: DateTime(2026, 1, 2)),
        person('뒤', checkIn: DateTime(2026, 1, 2), checkOut: d3),
      ];
      final e = ev(rooms: rooms, attendees: people);
      final r = distribute(e, people, rooms);
      expect(r.unplaced, isEmpty);
      expect(r.assignments.every((x) => x.room.roomNo == '301'), isTrue);
    });
  });

  group('방을 먼저 채운다 (흩어짐 방지)', () {
    test('그룹이 없는 사람들도 한 방을 채우고 다음 방으로 간다', () {
      // 예전엔 '여유 많은 방부터' 골라서 4인실 5개에 5명이 한 명씩 흩어졌다.
      final rooms = [for (var n = 301; n <= 305; n++) room('$n', 4)];
      final people = [for (var i = 0; i < 5; i++) person('P$i')];
      final e = ev(rooms: rooms, attendees: people);

      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);

      final byRoom = <String, int>{};
      for (final a in people) {
        byRoom[a.roomId!] = (byRoom[a.roomId!] ?? 0) + 1;
      }
      expect(byRoom['r301'], 4); // 첫 방을 꽉 채우고
      expect(byRoom['r302'], 1); // 남은 1명만 다음 방
      expect(byRoom.length, 2);
    });

    test('성별이 갈려도 각 성별끼리 방을 채운다', () {
      // 남3 여3, 4인실 4개. 성별 분리 ON.
      final rooms = [for (var n = 301; n <= 304; n++) room('$n', 4)];
      final people = [
        for (var i = 0; i < 3; i++) person('남$i'),
        for (var i = 0; i < 3; i++) person('여$i', gender: 'F'),
      ];
      final e = ev(rooms: rooms, attendees: people);

      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);

      expect(res.unplaced, isEmpty);
      // 방 2개만 써야 한다 (남자방 1, 여자방 1)
      expect(people.map((a) => a.roomId).toSet().length, 2);
    });

    test('큰 그룹은 방을 채우고 넘치는 만큼만 옆방으로', () {
      final rooms = [for (var n = 301; n <= 305; n++) room('$n', 4)];
      final people = [
        for (var i = 0; i < 6; i++) person('셀원$i', zone: 'A존', cell: '1셀'),
      ];
      final e = ev(rooms: rooms, attendees: people);

      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);

      final byRoom = <String, int>{};
      for (final a in people) {
        byRoom[a.roomId!] = (byRoom[a.roomId!] ?? 0) + 1;
      }
      expect(byRoom.length, 2);
      expect(byRoom.values.toList()..sort(), [2, 4]);
    });

    test('이미 사람이 있는 방을 먼저 채운다', () {
      // 301 에 1명 있고 302 는 비었다. 신규 2명은 301 을 채워야 한다.
      final rooms = [room('301', 4), room('302', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('기존', roomId: 'r301'),
          person('신규1'),
          person('신규2'),
        ],
      );
      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);
      expect(e.attendees.where((a) => a.roomId == 'r301').length, 3);
      expect(e.attendees.where((a) => a.roomId == 'r302'), isEmpty);
    });

    test('정원을 넘기지는 않는다', () {
      final rooms = [room('301', 2), room('302', 2)];
      final people = [for (var i = 0; i < 4; i++) person('P$i')];
      final e = ev(rooms: rooms, attendees: people);
      final res = autoAssign(e, AutoRule(priorityAge: null));
      applyAssignments(res.assignments);
      final s = Store()..event = e;
      expect(s.peakOccupancy(rooms[0]), 2);
      expect(s.peakOccupancy(rooms[1]), 2);
      expect(res.unplaced, isEmpty);
    });
  });

  group('다른 그룹과 섞이지 않는다', () {
    test('셀만 기준으로 뒀을 때 다른 셀과 한 방에 안 들어간다', () {
      // 4인실 3개. 1셀 2명, 2셀 2명 → 방을 채우겠다고 한 방에 몰면 안 된다.
      final rooms = [for (var n = 301; n <= 303; n++) room('$n', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('가1', cell: '1셀'),
          person('가2', cell: '1셀'),
          person('나1', cell: '2셀'),
          person('나2', cell: '2셀'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.cell]),
      );
      applyAssignments(res.assignments);

      for (final r in rooms) {
        final cells = e.attendees
            .where((a) => a.roomId == r.id)
            .map((a) => a.cell)
            .toSet();
        expect(
          cells.length,
          lessThanOrEqualTo(1),
          reason: '${r.roomNo}호에 $cells',
        );
      }
    });

    test('셀 없는 사람이 남의 셀 방에 끼지 않는다', () {
      final rooms = [room('301', 4), room('302', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('셀원1', cell: '1셀'),
          person('셀원2', cell: '1셀'),
          person('무소속'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.cell]),
      );
      applyAssignments(res.assignments);
      final loose = e.attendees.firstWhere((a) => a.name == '무소속');
      final cellRoom = e.attendees.firstWhere((a) => a.name == '셀원1').roomId;
      expect(loose.roomId, isNot(cellRoom));
    });

    test('빈 방이 없으면 그때는 섞는다 (자리부터 확보)', () {
      final e = ev(
        rooms: [room('301', 4)],
        attendees: [
          person('가1', cell: '1셀'),
          person('나1', cell: '2셀'),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.cell]),
      );
      expect(res.assignments.length, 2);
      expect(res.unplaced, isEmpty);
    });

    test('같은 셀은 여전히 한 방을 채운다', () {
      final rooms = [for (var n = 301; n <= 304; n++) room('$n', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [for (var i = 0; i < 4; i++) person('셀원$i', cell: '1셀')],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [GroupField.cell]),
      );
      applyAssignments(res.assignments);
      expect(e.attendees.map((a) => a.roomId).toSet().length, 1);
    });
  });

  group('우대 배정 구역', () {
    test('1~2층을 지정하면 우대 대상이 낮은 층부터 들어간다', () {
      // 1인실로 둬서 '나이 많은 순 → 낮은 층' 순서가 드러나게 한다.
      final rooms = [
        room('101', 1),
        room('201', 1),
        for (var n = 301; n <= 305; n++) room('$n', 4),
      ];
      final e = ev(
        rooms: rooms,
        attendees: [
          person('어르신1', age: 70),
          person('어르신2', age: 80),
          for (var i = 0; i < 3; i++) person('청년$i', age: 30),
        ],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: 65, floorMin: 1, floorMax: 2),
      );
      applyAssignments(res.assignments);
      // 나이 많은 순으로 낮은 층
      expect(e.attendees.firstWhere((a) => a.name == '어르신2').roomId, 'r101');
      expect(e.attendees.firstWhere((a) => a.name == '어르신1').roomId, 'r201');
    });

    test('지정 층에 자리가 없으면 다른 층으로 가고, 그 사실이 보고된다', () {
      // 1~2층이 아예 없는 건물
      final rooms = [for (var n = 301; n <= 303; n++) room('$n', 4)];
      final e = ev(
        rooms: rooms,
        attendees: [person('어르신', age: 70), person('청년', age: 30)],
      );
      final res = autoAssign(
        e,
        AutoRule(priorityAge: 65, floorMin: 1, floorMax: 2),
      );
      applyAssignments(res.assignments);
      expect(res.unplaced, isEmpty);
      expect(res.priorityOutsideZone.map((a) => a.name), ['어르신']);
    });

    test('우대 대상이 없으면 구역 설정은 아무 영향이 없다', () {
      final rooms = [room('101', 4), room('301', 4)];
      final e = ev(rooms: rooms, attendees: [person('청년', age: 30)]);
      final res = autoAssign(
        e,
        AutoRule(priorityAge: 65, floorMin: 1, floorMax: 2),
      );
      applyAssignments(res.assignments);
      expect(res.priorityOutsideZone, isEmpty);
      // 새 방을 열 때는 낮은 호수부터
      expect(e.attendees.single.roomId, 'r101');
    });
  });

  group('사용자 정의 참석자 항목', () {
    test('항목 추가/이름변경/삭제가 참석자 값까지 따라간다', () {
      final s = Store()..event = ev(attendees: [person('A'), person('B')]);
      expect(s.addCustomField('교회'), isTrue);
      expect(s.addCustomField('교회'), isFalse); // 중복
      expect(s.addCustomField('이름'), isFalse); // 기본 항목과 충돌
      expect(s.addCustomField('  '), isFalse);

      s.event.attendees[0].extra['교회'] = '한빛교회';
      expect(s.renameCustomField('교회', '소속교회'), isTrue);
      expect(s.event.customFields, ['소속교회']);
      expect(s.event.attendees[0].extra['소속교회'], '한빛교회');
      expect(s.event.attendees[0].extra.containsKey('교회'), isFalse);

      s.removeCustomField('소속교회');
      expect(s.event.customFields, isEmpty);
      expect(s.event.attendees[0].extra, isEmpty);
    });

    test('통합검색이 사용자 항목 값도 찾는다', () {
      final a = person('홍길동')..extra['교회'] = '한빛교회';
      final s = Store()..event = ev(attendees: [a, person('김철수')]);
      expect(s.search('한빛').single.name, '홍길동');
    });

    test('붙여넣기 컬럼에 사용자 항목이 들어오고 값이 파싱된다', () {
      final e = ev(customFields: ['교회']);
      expect(
        attendeeColumnOptions(e).containsKey(customFieldKey('교회')),
        isTrue,
      );

      final rows = parseAttendeeText(
        '홍길동\t남\t34\t한빛교회',
        columns: ['name', 'gender', 'age', customFieldKey('교회')],
        checkIn: d0,
        checkOut: d3,
        newId: nid,
      );
      expect(rows.single.attendee!.extra['교회'], '한빛교회');
    });

    test('JSON 왕복에서 항목 정의와 값이 보존된다', () {
      final a = person('홍길동')..extra['교회'] = '한빛교회';
      final e = ev(attendees: [a], customFields: ['교회']);
      final back = Event.fromJson(e.toJson());
      expect(back.customFields, ['교회']);
      expect(back.attendees.single.extra['교회'], '한빛교회');
    });

    test('예전 파일(항목 없음)도 그대로 열린다', () {
      final j = ev(attendees: [person('A')]).toJson();
      (j['attendees'] as List).first.remove('extra');
      j.remove('customFields');
      final back = Event.fromJson(j);
      expect(back.customFields, isEmpty);
      expect(back.attendees.single.extra, isEmpty);
    });

    test('사용자 항목을 자동배정 기준으로 쓸 수 있다', () {
      final e = ev(
        rooms: [room('101', 2), room('501', 2)],
        attendees: [
          person('A')..extra['교회'] = '한빛교회',
          person('B')..extra['교회'] = '한빛교회',
        ],
        customFields: ['교회'],
      );
      final church = GroupField.forEvent(e).firstWhere((f) => f.label == '교회');
      final res = autoAssign(e, AutoRule(priorityAge: null, groupBy: [church]));
      applyAssignments(res.assignments);
      expect(e.attendees.map((a) => a.roomId).toSet().length, 1);
      expect(res.assignments.every((x) => x.stage == '그룹'), isTrue);
    });

    test('교회가 1순위면 셀보다 교회를 먼저 지킨다', () {
      final e = ev(
        rooms: [room('101', 2), room('501', 2)],
        attendees: [
          person('기존', cell: '9셀', roomId: 'r101')..extra['교회'] = '한빛교회',
          person('기존2', cell: '1셀', roomId: 'r501')..extra['교회'] = '다른교회',
          person('신규', cell: '1셀')..extra['교회'] = '한빛교회',
        ],
        customFields: ['교회'],
      );
      final church = GroupField.forEvent(e).firstWhere((f) => f.label == '교회');
      final res = autoAssign(
        e,
        AutoRule(priorityAge: null, groupBy: [church, GroupField.cell]),
      );
      applyAssignments(res.assignments);
      // 셀이 같은 501 이 아니라, 교회가 같은 101 로 가야 한다.
      expect(e.attendees.firstWhere((a) => a.name == '신규').roomId, 'r101');
    });
  });

  group('건물', () {
    test('건물이 다르면 같은 호수도 따로 만들고, 같은 건물 안에서만 중복을 건너뛴다', () {
      final s = Store()..event = ev();
      expect(s.addRoomRange('101-103', capacity: 4, building: '반석관'), (3, 0));
      expect(s.addRoomRange('101-102', capacity: 4, building: '은혜관'), (2, 0));
      expect(s.addRoomRange('103-104', capacity: 4, building: ' 반석관 '), (1, 1));
      expect(s.addRoomRange('101', capacity: 4), (1, 0)); // 건물 없는 101 도 따로
      expect(s.event.rooms.map((r) => r.label), contains('반석관 104'));
      // 정렬: 건물 없는 방 → 건물 이름 순 → 호수 순
      expect((s.event.rooms..sort(byRoomNo)).map((r) => r.label).take(3), [
        '101',
        '반석관 101',
        '반석관 102',
      ]);
      expect(Event.fromJson(s.event.toJson()).rooms[1].building, '반석관');
    });

    test('자동배정: 배정할 건물을 고르면 그 건물 방에만 넣는다', () {
      final e = ev(
        rooms: [
          Room(id: 'a', roomNo: '101', building: '반석관', capacity: 2),
          Room(id: 'b', roomNo: '101', building: '은혜관', capacity: 2),
        ],
        attendees: [person('A'), person('B'), person('C')],
      );
      final res = autoAssign(e, AutoRule(buildings: {'은혜관'}));
      expect(res.assignments.map((x) => x.room.id).toSet(), {'b'});
      expect(res.unplaced, hasLength(1)); // 반석관은 비어 있어도 쓰지 않는다
    });

    test('자동배정: 우대 구역을 건물까지 좁힌다', () {
      Event e() => ev(
        rooms: [
          Room(id: 'a', roomNo: '101', building: '반석관', capacity: 1),
          Room(id: 'b', roomNo: '101', building: '은혜관', capacity: 1),
        ],
        attendees: [person('어르신', age: 70)],
      );
      AutoRule rule([String? b]) => AutoRule(
        priorityAge: 65,
        floorMin: 1,
        floorMax: 1,
        priorityBuilding: b,
      );
      // 건물을 안 고르면 이름 순으로 반석관부터
      expect(autoAssign(e(), rule()).assignments.single.room.id, 'a');
      expect(autoAssign(e(), rule('은혜관')).assignments.single.room.id, 'b');
    });

    test('자리 옮기기는 같은 건물·같은 층 방끼리만 자리를 바꾼다', () {
      final a = Room(id: 'a', roomNo: '101', building: '반석관', capacity: 4);
      final b = Room(id: 'b', roomNo: '101', building: '은혜관', capacity: 4);
      final s = Store()..event = ev(rooms: [a, b]);
      s.moveRoom(a, 0, cols: 5);
      // 은혜관 101 을 0번으로 옮겨도 반석관 101 과 자리를 바꾸지 않는다 (격자가 따로다)
      s.moveRoom(b, 0, cols: 5);
      expect((a.slot, b.slot), (0, 0));
    });
  });

  group('저장/불러오기', () {
    test('JSON 왕복', () {
      final e = ev(
        rooms: [room('101', 2, gender: 'F')],
        attendees: [person('홍길동', cell: '1셀', zone: 'A', roomId: 'r101')],
      );
      final back = Event.fromJson(e.toJson());
      expect(back.rooms.single.gender, 'F');
      expect(back.attendees.single.cell, '1셀');
      expect(back.attendees.single.roomId, 'r101');
      expect(back.nights.length, 3);
    });

    test('서버 문서가 깨져 있으면 저장하지 않는다 (빈 화면으로 덮어쓰지 않게)', () async {
      final r = PlanRemote()
        ..data = {'name': '잘린'}
        ..version = 3;
      remote = r;
      final s = Store();
      await s.open('g1', ev());
      expect(s.loadError, isNotNull);
      s.commit();
      await s.pendingWrites;
      expect(r.saves, 0);
    });

    test('저장 후 다시 열면 그대로다', () async {
      remote = PlanRemote();
      final s = Store();
      await s.open('g1', ev(rooms: [room('101', 2)]));
      s.event.attendees.add(person('홍길동'));
      s.commit();
      await s.pendingWrites;
      final s2 = Store();
      await s2.open('g1', ev());
      expect(s2.loadError, isNull);
      expect(s2.event.rooms.single.roomNo, '101');
      expect(s2.event.attendees.single.name, '홍길동');
    });

    test('연달아 바꿔도 한 번에 하나씩 올리고 마지막 상태가 남는다', () async {
      final r = PlanRemote();
      remote = r;
      final s = Store();
      await s.open('g1', ev());
      for (var i = 0; i < 10; i++) {
        s.event.attendees.add(person('p$i'));
        s.commit();
      }
      await s.pendingWrites;
      expect(r.saves, 2); // 첫 변경 + 올리는 동안 쌓인 변경 한 번
      expect(r.data!['attendees'] as List, hasLength(10));
    });

    test('다른 기기가 먼저 저장했으면 덮어쓰지 않고 그 내용을 불러온다', () async {
      final r = PlanRemote();
      remote = r;
      final a = Store(), b = Store();
      await a.open('g1', ev());
      await b.open('g1', ev());
      b.event.attendees.add(person('B가 추가'));
      b.commit();
      await b.pendingWrites;

      a.event.attendees.add(person('A가 추가'));
      a.commit();
      await a.pendingWrites;
      expect((r.data!['attendees'] as List).single['name'], 'B가 추가');
      expect(a.event.attendees.single.name, 'B가 추가');
      expect(a.saveError, contains('다른 기기'));

      // 그다음 변경은 최신 버전 위에 저장된다
      a.commit();
      await a.pendingWrites;
      expect(r.version, 2);
      expect(a.saveError, isNull);
    });

    test('집회를 열기만 해서는 저장하지 않는다 (다른 기기와 괜한 충돌 방지)', () async {
      final r = PlanRemote();
      remote = r;
      final s = Store();
      await s.open('g1', ev());
      s.applyGathering(Gathering(name: 't', start: d0, end: d3));
      await s.pendingWrites;
      expect(r.saves, 0);
    });
  });

  group('방 자리 배치 (드래그 앤 드롭)', () {
    test('자리를 안 정했으면 호수 순으로 앞에서부터 채운다', () {
      final rooms = [room('303', 4), room('301', 4), room('302', 4)];
      final grid = layoutSlots(rooms, 5);
      expect(grid.length, 5); // 줄 끝까지 채워서 돌려준다
      expect(grid.take(3).map((r) => r?.roomNo).toList(), [
        '301',
        '302',
        '303',
      ]);
      expect(grid.skip(3).every((r) => r == null), isTrue);
    });

    test('자리가 박힌 방은 그 자리에 있고 사이는 빈 칸으로 남는다', () {
      final rooms = [
        room('301', 4)..slot = 0,
        room('302', 4)..slot = 4, // 복도 건너편
      ];
      final grid = layoutSlots(rooms, 5);
      expect(grid.map((r) => r?.roomNo).toList(), [
        '301',
        null,
        null,
        null,
        '302',
      ]);
    });

    test('빈 줄까지 자리를 잡으면 격자가 그만큼 늘어난다', () {
      final grid = layoutSlots([room('301', 4)..slot = 7], 5);
      expect(grid.length, 10);
      expect(grid[7]?.roomNo, '301');
    });

    test('같은 자리를 두 방이 주장하면 밀린 방도 사라지지 않는다', () {
      final rooms = [room('301', 4)..slot = 2, room('302', 4)..slot = 2];
      final grid = layoutSlots(rooms, 5);
      expect(grid.whereType<Room>().length, 2);
      expect(grid[2]?.roomNo, '301'); // 호수가 빠른 쪽이 자리를 갖는다
    });

    test('망가진 자리 번호는 자동 배치로 되돌린다', () {
      final grid = layoutSlots([
        room('301', 4)..slot = -3,
        room('302', 4)..slot = 999999,
      ], 5);
      expect(grid.take(2).map((r) => r?.roomNo).toList(), ['301', '302']);
    });

    test('빈 칸으로 옮기면 그 자리로 가고 옆방은 그대로 있다', () async {
      final store = Store();
      store.event = ev(rooms: [room('301', 4), room('302', 4)]);
      store.moveRoom(store.event.rooms[0], 3, cols: 5);
      await store.pendingWrites;
      expect(store.event.rooms[0].slot, 3);
      // 옮기기 전 배치를 굳히므로 안 건드린 방은 제자리에 남는다
      expect(store.event.rooms[1].slot, 1);
    });

    test('다른 방 위에 놓으면 서로 자리를 바꾼다', () async {
      final store = Store();
      store.event = ev(rooms: [room('301', 4), room('302', 4)]);
      store.moveRoom(store.event.rooms[0], 1, cols: 5);
      await store.pendingWrites;
      expect(store.event.rooms[0].slot, 1);
      expect(store.event.rooms[1].slot, 0);
    });

    test('층이 달라도 자리 번호는 서로 간섭하지 않는다', () async {
      final store = Store();
      store.event = ev(rooms: [room('301', 4), room('401', 4)]);
      store.moveRoom(store.event.rooms[1], 2, cols: 5);
      await store.pendingWrites;
      expect(store.event.rooms[1].slot, 2);
      // 3층은 아예 건드리지 않는다 (자리 번호가 층마다 따로 매겨진다)
      expect(store.event.rooms[0].slot, isNull);
      expect(layoutSlots([store.event.rooms[0]], 5).first?.roomNo, '301');
    });

    test('배치 초기화하면 자리가 전부 지워진다', () async {
      final store = Store();
      store.event = ev(rooms: [room('301', 4)..slot = 6, room('302', 4)]);
      store.resetLayout();
      await store.pendingWrites;
      expect(store.event.rooms.every((r) => r.slot == null), isTrue);
    });

    test('자리는 저장 파일에 남는다', () {
      final e = ev(rooms: [room('301', 4)..slot = 5]);
      final back = Event.fromJson(e.toJson());
      expect(back.rooms.single.slot, 5);
    });

    test('자리가 없던 예전 파일도 그대로 열린다', () {
      final j = {
        'name': 't',
        'startDate': d0.toIso8601String(),
        'endDate': d3.toIso8601String(),
        'rooms': [
          {'id': 'r1', 'roomNo': '301', 'capacity': 4},
        ],
        'attendees': [],
      };
      expect(Event.fromJson(j).rooms.single.slot, isNull);
    });
  });
}
