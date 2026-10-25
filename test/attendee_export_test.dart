import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/store.dart';
import 'package:xml/xml.dart';
import 'package:room_assignment/xlsx_export.dart';

final d1 = DateTime(2026, 10, 9), d4 = DateTime(2026, 10, 12);

Attendee att(String name, {String? note, String? room, String? reg}) =>
    Attendee(
      id: 'p-$name',
      name: name,
      gender: 'F',
      age: 30,
      phone: '010-1234-5678',
      note: note,
      roomId: room,
      checkIn: d1,
      checkOut: DateTime(2026, 10, 10),
      extra: {'교회': '한빛'},
      registrationId: reg,
    );

/// 행을 떼기 전의 attendeesCsv 그대로 — 결과가 한 글자도 안 바뀌었는지 대조한다.
String oldCsv(Event e, [List<Attendee>? people]) {
  final rooms = {for (final r in e.rooms) r.id: r.label};
  String cell(Object? v) {
    var s = '${v ?? ''}';
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
      '입금',
    ],
    for (final a in people ?? e.attendees)
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
        switch (a.pay) {
          payPending => '입금대기',
          _ => a.registrationId == null ? '' : '입금확인',
        },
      ],
  ].map((row) => row.map(cell).join(',')).join('\r\n');
}

void main() {
  final e = Event(name: 'x', startDate: d1, endDate: d4, customFields: ['교회']);
  e.rooms.add(Room(id: 'r1', roomNo: '101', capacity: 4));
  e.attendees.addAll([
    att('가', note: '=1+1', room: 'r1', reg: 'g1'),
    att('나', note: '따옴표 "x", 줄\n바꿈')..pay = payPending,
    att('다'),
  ]);

  test('[백업] CSV 는 행을 떼어낸 뒤에도 바이트까지 같다', () {
    expect(attendeesCsv(e), oldCsv(e));
    expect(attendeesCsv(e, [e.attendees[1]]), oldCsv(e, [e.attendees[1]]));
  });

  test('xlsx: 시트 이름·내용, 수식은 글자로, 제어문자는 빠진다', () {
    final rows = attendeeRows(e, e.attendees);
    final bytes = xlsxBytes([
      ('전체', rows),
      (
        '10-09(금)',
        [
          rows.first,
          ['\u0001한글 <&>'],
        ],
      ),
    ]);
    final zip = ZipDecoder().decodeBytes(bytes);
    XmlDocument doc(String name) => XmlDocument.parse(
      utf8.decode(zip.findFile(name)!.content as List<int>),
    );
    for (final f in [
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/_rels/workbook.xml.rels',
    ]) {
      doc(f); // 구조가 올바른 XML 인지
    }
    expect(
      doc('xl/workbook.xml')
          .findAllElements('sheet')
          .map((s) => s.getAttribute('name')),
      ['전체', '10-09(금)'],
    );
    List<List<String>> cells(int i) => [
      for (final r in doc('xl/worksheets/sheet$i.xml').findAllElements('row'))
        [for (final t in r.findAllElements('t')) t.innerText],
    ];
    final one = cells(1);
    expect(one.length, 4, reason: '머리글 + 3명');
    expect(one.first, rows.first.map((v) => '$v').toList());
    expect(one[1], contains('=1+1'));
    expect(
      doc('xl/worksheets/sheet1.xml').findAllElements('f'),
      isEmpty,
      reason: '수식 셀이 없다',
    );
    expect(one[2], contains('따옴표 "x", 줄\n바꿈'));
    expect(cells(2)[1], ['한글 <&>']);
  });

  test('comesOn: 1·2·4일 신청자는 4일에 오고 3일엔 안 온다, 취소는 안 온다', () {
    final g = Gathering(id: 'g', name: 'x', start: d1, end: d4);
    final s = Store()..event = e;
    Person p(String id) => Person(
      id: id,
      name: id,
      gender: 'M',
      birthYear: 1990,
      days: [d1, DateTime(2026, 10, 10), d4],
    );
    Registration r(String id, RegStatus st) => Registration(
      id: id,
      gatheringId: 'g',
      phone: '01012345678',
      people: [p('p-$id')],
      status: st,
      createdAt: d1,
    );
    final regs = [r('떨어진날', RegStatus.pending), r('취소', RegStatus.cancelled)];
    final comes = s.comesOn(g, regs);
    final a = att('떨어진날');
    expect(comes(a, d4), isTrue);
    expect(comes(a, DateTime(2026, 10, 11)), isFalse);
    // 취소 신청은 참석일로 보지 않아 일정(9일 1박)만 본다.
    expect(comes(att('취소'), d4), isFalse);
    expect(s.everyone(g, regs).map((x) => x.name), isNot(contains('취소')));
  });
}
