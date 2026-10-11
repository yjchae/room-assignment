// 은행 내역으로 자동 입금 확인. 파일 읽기(농협 xls·xlsx·csv)와 신청 대조 규칙을 본다.
// 실제 은행 파일은 실명이 들어 있어서 커밋하지 않는다 — 여기서 같은 모양의 가짜 파일을 만든다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/bank_import.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/screens/registrations.dart' show BankPreview;

/// 농협 인터넷뱅킹 거래내역 모양: 위에 계좌 정보 몇 줄, 머리줄, 거래, 합계 줄.
const _nh = [
  ['거래내역조회'],
  ['계좌번호', '301-0000-0000-00'],
  ['조회기간', '2026.10.01 ~ 2026.10.11'],
  <Object>[],
  [
    '구분',
    '거래일시',
    '출금금액(원)',
    '입금금액(원)',
    '거래 후 잔액(원)',
    '거래내용',
    '거래기록사항',
    '거래점',
    '거래메모',
  ],
  [
    '1',
    '2026/10/03 14:22:05',
    '0',
    '415,000',
    '1,415,000',
    '타행이체',
    '홍길동',
    '농협',
    '',
  ],
  [
    '2',
    '2026/10/04 09:00:00',
    '50,000',
    '0',
    '1,365,000',
    '체크카드',
    '마트',
    '',
    '',
  ],
  [
    '3',
    '2026/10/05 10:10:10',
    '0',
    '200,000',
    '1,565,000',
    '인터넷',
    '김철수',
    '',
    '',
  ],
  ['', '합계', '50,000', '615,000', '', '', '', '', ''],
];

Registration reg(
  String id,
  String name, {
  DateTime? at,
  String? depositor,
  RegStatus status = RegStatus.pending,
  String? ref,
}) => Registration(
  id: id,
  gatheringId: 'g',
  phone: '01012345678',
  people: [Person(name: name, gender: 'M', birthYear: 1990)],
  depositor: depositor,
  status: status,
  paidRef: ref,
  createdAt: at ?? DateTime(2026, 10, 1, 12),
);

void main() {
  group('파일 읽기', () {
    void expectNh(List<BankTx> txs) {
      expect(txs.map((t) => (t.name, t.amount)), [
        ('홍길동', 415000),
        ('김철수', 200000),
      ]);
      expect(txs.first.at, DateTime(2026, 10, 3, 14, 22, 5));
      expect(txs.first.ref, '2026-10-03 14:22:05|415000|홍길동');
    }

    test('csv: 머리줄 위 잡줄과 출금·합계 줄을 건너뛴다', () {
      final csv = [for (final r in _nh) r.map((c) => '"$c"').join(',')]
          .join('\r\n');
      expectNh(
        parseBankFile(Uint8List.fromList(utf8.encode('﻿$csv')), 'a.csv'),
      );
    });

    test('xlsx', () => expectNh(parseBankFile(_xlsx(_nh), 'a.xlsx')));

    test('xls (농협) — 미니 스트림 / 일반 스트림, SST 가 CONTINUE 로 잘린 경우', () {
      expectNh(parseBankFile(_xls(_nh), 'a.xls'));
      expectNh(parseBankFile(_xls(_nh, pad: 5000), 'a.xls'));
    });

    test('HTML 로 된 xls', () {
      final html =
          '<table>${[for (final r in _nh) '<tr>${r.map((c) => '<td>$c</td>').join()}</tr>'].join()}</table>';
      expectNh(parseBankFile(Uint8List.fromList(utf8.encode(html)), 'a.xls'));
    });

    test('날짜·시간 칸이 나뉜 은행, 엑셀 날짜 숫자', () {
      final txs = bankRows([
        ['거래일자', '거래시간', '적요', '입금액'],
        [46298.0, '14:22:05', '홍길동', 415000.0],
      ]);
      expect(txs.single.at, DateTime(2026, 10, 3, 14, 22, 5));
    });

    test('머리줄이 없으면 안내 문구', () {
      expect(
        () => bankRows([
          ['아무거나'],
        ]),
        throwsFormatException,
      );
    });
  });

  group('대조', () {
    final txs = bankRows(_nh.map((r) => r.cast<Object?>()).toList());

    test('이름·금액이 같으면 확실, 금액이 다르면 확인 필요, 못 맞춘 입금은 따로', () {
      final r = matchDeposits(
        txs,
        [reg('a', '홍길동'), reg('b', '김철수')],
        {'a': 415000, 'b': 210000},
      );
      expect(r.matches.map((m) => (m.reg.id, m.issue)), [
        ('a', null),
        ('b', '10,000원 덜 입금'),
      ]);
      expect(r.unmatched, isEmpty);
    });

    test('입금자명을 따로 적었으면 그 이름으로, 공백·괄호·끝 숫자는 무시', () {
      final t = bankRows([
        ['거래일시', '입금금액(원)', '거래기록사항'],
        ['2026-10-03 10:00', '415000', '홍 길동1003'],
      ]);
      final r = matchDeposits(
        t,
        [reg('a', '홍아들', depositor: '홍길동')],
        {'a': 415000},
      );
      expect(r.matches.single.issue, isNull);
    });

    test('동명이인이 같은 금액이면 둘 다 확인 필요', () {
      final r = matchDeposits(
        txs,
        [reg('a', '홍길동'), reg('b', '홍길동')],
        {'a': 415000, 'b': 415000},
      );
      expect(r.matches.map((m) => m.issue), everyElement(isNotNull));
    });

    test('더 낸 입금은 차액을 적는다', () {
      final r = matchDeposits(txs, [reg('a', '홍길동')], {'a': 400000});
      expect(r.matches.single.issue, '15,000원 더 입금');
      expect(r.matches.single.due, 400000);
    });

    test('덜 내고 확인된 신청에 부족분이 들어오면 추가 입금', () {
      final t = bankRows([
        ['거래일시', '입금금액(원)', '거래기록사항'],
        ['2026-10-03 10:00', '400000', '홍길동'],
        ['2026-10-06 10:00', '15000', '홍길동'],
      ]);
      final first = t.first;
      final paid = reg('a', '홍길동', status: RegStatus.confirmed, ref: first.ref)
        ..paid = 400000;
      final r = matchDeposits(t, [paid], {'a': 415000});
      expect(r.matches.single.tx.amount, 15000);
      expect(r.matches.single.due, 15000);
      expect(r.matches.single.issue, startsWith('추가 입금'));
      // 추가 입금까지 반영하면 두 거래 모두 쓴 것이 돼서 다시 올려도 안 나온다.
      paid
        ..paid = 415000
        ..paidRef = '${first.ref}\n${t.last.ref}';
      expect(matchDeposits(t, [paid], {'a': 415000}).matches, isEmpty);
    });

    testWidgets('미리보기: 확실은 체크, 차액 표시, 같은 입금은 한 번만', (t) async {
      final r = matchDeposits(
        txs,
        [reg('a', '홍길동'), reg('b', '홍길동'), reg('c', '김철수')],
        {'a': 415000, 'b': 415000, 'c': 210000},
      );
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BankPreview(
              matches: r.matches,
              unmatched: r.unmatched,
              txCount: txs.length,
            ),
          ),
        ),
      );
      expect(find.text('10,000원 덜 입금'), findsWidgets);
      expect(find.text('0건 입금 확인'), findsOneWidget);
      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(find.text('1건 입금 확인'), findsOneWidget);
      // 같은 입금을 쓰는 다른 홍길동 줄은 막힌다.
      expect(find.textContaining('다른 신청에 쓴 입금'), findsOneWidget);
    });

    test('신청일 전 입금, 이미 다른 신청에 쓴 입금은 보지 않는다', () {
      final late = matchDeposits(
        txs,
        [reg('a', '홍길동', at: DateTime(2026, 10, 4))],
        {'a': 415000},
      );
      expect(late.matches, isEmpty);
      final used = matchDeposits(
        txs,
        [
          reg('a', '홍길동'),
          reg('x', '누군가', status: RegStatus.confirmed, ref: txs.first.ref),
        ],
        {'a': 415000, 'x': 0},
      );
      expect(used.matches, isEmpty);
      expect(used.unmatched.map((t) => t.name), ['김철수']);
    });
  });
}

// ---------------------------------------------------------------------------
// 가짜 엑셀 파일 만들기
// ---------------------------------------------------------------------------

Uint8List _xlsx(List<List<Object>> rows) {
  final strings = <String>[];
  String col(int i) => String.fromCharCode(65 + i);
  final sheet = StringBuffer(
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      strings.add('${rows[r][c]}');
      sheet.write(
        '<c r="${col(c)}${r + 1}" t="s"><v>${strings.length - 1}</v></c>',
      );
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final sst =
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '${strings.map((s) => '<si><t>$s</t></si>').join()}</sst>';
  final a = Archive()
    ..add(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(sst)))
    ..add(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode('$sheet')));
  return ZipEncoder().encodeBytes(a);
}

/// BIFF8 통합문서를 OLE 복합 문서에 넣는다. 금액 칸은 숫자(NUMBER·RK)로, 나머지는 SST 글자로.
/// 마지막 글자는 SST 와 CONTINUE 사이에서 반으로 잘라 둔다. [pad] 만큼 빈 레코드를 붙이면 4096 바이트를
/// 넘어 일반 스트림이 된다(작으면 미니 스트림).
Uint8List _xls(List<List<Object>> rows, {int pad = 0}) {
  final out = BytesBuilder();
  void rec(int type, List<int> data) {
    out.add(_le(type, 2) + _le(data.length, 2) + data);
  }

  List<int> str(String s) => [
    ..._le(s.length, 2),
    1,
    for (final c in s.codeUnits) ..._le(c, 2),
  ];
  final strings = <String>[];
  final cells = <List<int>>[];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final v = '${rows[r][c]}';
      final n = int.tryParse(v.replaceAll(',', ''));
      if (r > 4 && (c == 2 || c == 3) && n != null) {
        // 입금은 NUMBER, 출금은 RK(정수) 로 — 두 가지를 다 읽는지 본다.
        cells.add(
          c == 3
              ? [
                  ..._le(0x0203, 2),
                  ..._le(14, 2),
                  ..._le(r, 2),
                  ..._le(c, 2),
                  0,
                  0,
                  ...(ByteData(8)..setFloat64(0, n.toDouble(), Endian.little))
                      .buffer
                      .asUint8List(),
                ]
              : [
                  ..._le(0x027E, 2),
                  ..._le(10, 2),
                  ..._le(r, 2),
                  ..._le(c, 2),
                  0,
                  0,
                  ..._le(n << 2 | 2, 4),
                ],
        );
      } else {
        strings.add(v);
        cells.add([
          ..._le(0x00FD, 2),
          ..._le(10, 2),
          ..._le(r, 2),
          ..._le(c, 2),
          0,
          0,
          ..._le(strings.length - 1, 4),
        ]);
      }
    }
  }
  strings.add('끝글자');
  rec(0x0809, [0, 6, 5, 0, ...List.filled(12, 0)]);
  final body = [for (final s in strings.take(strings.length - 1)) ...str(s)];
  rec(0x00FC, [
    ..._le(strings.length, 4),
    ..._le(strings.length, 4),
    ...body,
    3,
    0,
    1,
    ..._le('끝'.codeUnitAt(0), 2),
  ]);
  rec(0x003C, [1, for (final c in '글자'.codeUnits) ..._le(c, 2)]);
  for (var i = 0; i < pad ~/ 4; i++) {
    rec(0x00E1, []); // 아무 뜻 없는 빈 레코드
  }
  rec(0x000A, []);
  rec(0x0809, [0, 6, 0x10, 0, ...List.filled(12, 0)]);
  for (final c in cells) {
    out.add(c);
  }
  rec(0x000A, []);
  return _cfb(out.takeBytes());
}

List<int> _le(int v, int n) => [
  for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xFF,
];

/// 512 바이트 섹터의 OLE 복합 문서. 섹터 0 = FAT, 1 = 디렉터리, 2 = 미니 FAT, 3~ = 데이터.
Uint8List _cfb(Uint8List book) {
  const end = 0xFFFFFFFE, free = 0xFFFFFFFF;
  final mini = book.length < 4096;
  Uint8List pad(List<int> b, int unit) =>
      Uint8List(((b.length + unit - 1) ~/ unit) * unit)..setAll(0, b);
  final data = pad(book, 512);
  final dataSecs = data.length ~/ 512;
  final fat = List.filled(128, free);
  fat[0] = 0xFFFFFFFD;
  fat[1] = end;
  fat[2] = end;
  for (var i = 0; i < dataSecs; i++) {
    fat[3 + i] = i == dataSecs - 1 ? end : 4 + i;
  }
  final miniFat = List.filled(128, free);
  final miniSecs = (book.length + 63) ~/ 64;
  for (var i = 0; i < miniSecs; i++) {
    miniFat[i] = i == miniSecs - 1 ? end : i + 1;
  }
  List<int> entry(String name, int type, int start, int size) {
    final e = Uint8List(128);
    for (var i = 0; i < name.length; i++) {
      e.setAll(i * 2, _le(name.codeUnitAt(i), 2));
    }
    e.setAll(64, _le((name.length + 1) * 2, 2));
    e[66] = type;
    e.setAll(68, _le(free, 4) + _le(free, 4) + _le(type == 5 ? 1 : free, 4));
    e.setAll(116, _le(start, 4) + _le(size, 4));
    return e;
  }

  final head = Uint8List(512)
    ..setAll(0, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    ..setAll(
      0x18,
      _le(0x3E, 2) + _le(3, 2) + _le(0xFFFE, 2) + _le(9, 2) + _le(6, 2),
    )
    ..setAll(0x2C, _le(1, 4) + _le(1, 4) + _le(0, 4) + _le(4096, 4))
    ..setAll(
      0x3C,
      _le(mini ? 2 : end, 4) + _le(mini ? 1 : 0, 4) + _le(end, 4) + _le(0, 4),
    );
  for (var i = 0; i < 109; i++) {
    head.setAll(0x4C + i * 4, _le(i == 0 ? 0 : free, 4));
  }
  final dir = pad([
    ...entry('Root Entry', 5, mini ? 3 : end, mini ? miniSecs * 64 : 0),
    ...entry('Workbook', 2, mini ? 0 : 3, book.length),
  ], 512);
  return Uint8List.fromList([
    ...head,
    for (final f in fat) ..._le(f, 4),
    ...dir,
    for (final f in miniFat) ..._le(f, 4),
    ...data,
  ]);
}
