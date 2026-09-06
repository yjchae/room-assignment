import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/auth.dart';
import 'package:room_assignment/auto_assign.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/store.dart';

final d0 = DateTime(2026, 1, 1);
final d3 = DateTime(2026, 1, 4); // 3박

int _n = 0;
String nid() => 'id${_n++}';

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

    test('깨진 파일은 옆으로 치우고 빈 집회로 시작한다', () async {
      final dir = Directory.systemTemp.createTempSync('room_assign_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/event.json')
        ..writeAsStringSync('{"name": "잘린');
      final s = Store(fileOverride: f);
      await s.load();
      expect(s.loadError, isNotNull);
      expect(s.event.attendees, isEmpty);
      expect(File('${f.path}.corrupt').existsSync(), isTrue);
    });

    test('저장 후 다시 읽으면 그대로다', () async {
      final dir = Directory.systemTemp.createTempSync('room_assign_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/event.json');
      final s = Store(fileOverride: f)
        ..event = ev(rooms: [room('101', 2)], attendees: [person('홍길동')]);
      await s.load();
      s.event = ev(rooms: [room('101', 2)], attendees: [person('홍길동')]);
      s.commit();
      await s.pendingWrites;
      final s2 = Store(fileOverride: f);
      await s2.load();
      expect(s2.loadError, isNull);
      expect(s2.event.attendees.single.name, '홍길동');
    });
  });

  group('비밀번호', () {
    test('설정 → 확인', () async {
      final dir = Directory.systemTemp.createTempSync('room_assign_auth');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/auth.json');
      final a = Auth(fileOverride: f);
      await a.load();
      expect(a.isSet, isFalse);
      await a.setPassword('1234');
      final b = Auth(fileOverride: f);
      await b.load();
      expect(b.check('1234'), isTrue);
      expect(b.check('4321'), isFalse);
    });

    test('salt 가 없는 반쪽 파일은 미설정으로 본다 (잠금화면에서 크래시 금지)', () async {
      final dir = Directory.systemTemp.createTempSync('room_assign_auth');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/auth.json')
        ..writeAsStringSync('{"hash":"deadbeef"}');
      final a = Auth(fileOverride: f);
      await a.load();
      expect(a.isSet, isFalse);
      expect(a.check('아무거나'), isFalse);
    });
  });
}
