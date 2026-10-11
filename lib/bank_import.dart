import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'gathering.dart';
import 'models.dart' show dateOnly;

/// 은행 입출금 내역의 입금 한 건.
class BankTx {
  BankTx({required this.at, required this.amount, required this.texts});

  final DateTime at;
  final int amount;

  /// 입금자가 들어 있을 만한 칸들(거래기록사항·적요·내용…). 은행마다 이름이 다른 칸에 들어가서 다 들고 있다.
  final List<String> texts;

  String get name => texts.firstWhere((t) => t.isNotEmpty, orElse: () => '');

  /// 같은 거래를 두 번 쓰지 않게 신청의 `paid_ref` 에 남기는 값. 같은 파일을 다시 올리면 같은 값이 나온다.
  String get ref => '${ymd(at)} ${_hms(at)}|$amount|$name';
}

String _hms(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 대조 결과 한 줄. [due] = 이 입금으로 받아야 할 금액(입금대기는 계산 금액, 추가 입금은 부족분).
/// [issue] 가 null 이면 확실(미리 체크), 있으면 운영자가 보고 고른다.
typedef BankMatch = ({Registration reg, BankTx tx, int due, String? issue});

/// 입금액 − 받을 금액을 "10,000원 더 입금" / "10,000원 덜 입금" 으로. 같으면 null.
String? diffText(int paid, int due) => paid == due
    ? null
    : '${won((paid - due).abs())} ${paid > due ? '더' : '덜'} 입금';

/// 신청에 남은 근거 거래들. 덜 낸 뒤 추가로 보낸 입금은 줄을 바꿔 덧붙인다.
List<String> paidRefs(Registration r) =>
    (r.paidRef ?? '').split('\n').where((s) => s.isNotEmpty).toList();

/// 은행에서 내려받은 파일(xlsx · xls · csv)에서 입금만 뽑는다. 못 읽으면 [FormatException] (안내 문구).
///
/// 농협 인터넷뱅킹 기준(거래일시 · 입금금액(원) · 거래기록사항)으로 맞췄고, 다른 은행 칸 이름도 몇 개 받는다.
List<BankTx> parseBankFile(Uint8List bytes, String fileName) =>
    bankRows(_readTable(bytes));

List<List<Object?>> _readTable(Uint8List b) {
  bool sig(List<int> s) =>
      b.length >= s.length &&
      [for (var i = 0; i < s.length; i++) b[i] == s[i]].every((x) => x);
  if (sig([0xD0, 0xCF, 0x11, 0xE0])) return _readXls(b);
  if (sig([0x50, 0x4B, 0x03, 0x04])) return _readXlsx(b);
  final String text;
  try {
    text = utf8.decode(b).replaceFirst('﻿', '');
  } on FormatException {
    // 엑셀에서 그냥 'CSV' 로 저장하면 EUC-KR 이다. 웹·데스크톱 모두 기본 디코더가 없다.
    throw const FormatException(
      '파일을 읽지 못했습니다. 은행에서 받은 엑셀(xls·xlsx) 그대로 올리거나 "CSV UTF-8" 로 저장해 올려주세요.',
    );
  }
  return text.contains('<tr') || text.contains('<TR')
      ? _readHtml(text)
      : _readCsv(text);
}

/// 표에서 머리줄을 찾아 입금 행만 뽑는다. 테스트가 표를 바로 넣으려고 공개해 둔다.
List<BankTx> bankRows(List<List<Object?>> rows) {
  String n(Object? c) => '${c ?? ''}'.replaceAll(RegExp(r'\s'), '');
  for (var h = 0; h < rows.length && h < 30; h++) {
    final head = [for (final c in rows[h]) n(c)];
    int find(bool Function(String) f) => head.indexWhere(f);
    final date = find(
      (s) => s.contains('거래일') || s.contains('일시') || s == '일자' || s == '날짜',
    );
    final time = find((s) => s.contains('거래시간') || s == '시간');
    final money = find(
      (s) =>
          (s.contains('입금') && !s.contains('입금자') && !s.contains('입금인')) ||
          s.contains('맡기신'),
    );
    // 앞에 있는 이름일수록 입금자가 들어 있을 가능성이 높다. 농협은 '거래기록사항'에 보낸 사람이 찍힌다.
    final names = <int>{
      for (final k in [
        '거래기록사항',
        '입금자',
        '보낸분',
        '보내는분',
        '의뢰인',
        '기재내용',
        '적요',
        '내용',
        '메모',
      ])
        for (var i = 0; i < head.length; i++)
          if (head[i].contains(k)) i,
    };
    if (date < 0 || money < 0 || names.isEmpty) continue;
    Object? at(List<Object?> r, int i) => i >= 0 && i < r.length ? r[i] : null;
    return [
      for (final r in rows.skip(h + 1))
        if (_amount(at(r, money)) case final a? when a > 0)
          if (_date(at(r, date), at(r, time)) case final d?)
            BankTx(
              at: d,
              amount: a,
              texts: [for (final i in names) '${at(r, i) ?? ''}'.trim()],
            ),
    ];
  }
  throw const FormatException(
    '입금금액·거래일시 칸을 찾지 못했습니다. 은행에서 받은 입출금 내역 파일인지 확인하세요.',
  );
}

int? _amount(Object? c) {
  if (c is num) return c.round();
  final d = '${c ?? ''}'.replaceAll(RegExp(r'[,원\s]'), '');
  return d.isEmpty ? null : num.tryParse(d)?.round();
}

DateTime? _date(Object? c, Object? time) {
  DateTime? d;
  if (c is num && c > 20000) {
    // 엑셀 날짜 일련번호 (1900 체계). 소수부가 시각.
    d = DateTime(
      1899,
      12,
      30,
    ).add(Duration(milliseconds: (c * 86400000).round()));
  } else {
    final m = RegExp(
      r'(\d{4})\D{0,2}(\d{1,2})\D{0,2}(\d{1,2})(?:\D+(\d{1,2}):?(\d{2}):?(\d{2})?)?',
    ).firstMatch('${c ?? ''}');
    if (m == null) return null;
    int g(int i) => int.parse(m[i] ?? '0');
    d = DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
  }
  // 거래일자와 거래시간이 나뉜 은행.
  final t = RegExp(r'(\d{1,2}):?(\d{2}):?(\d{2})?').firstMatch('${time ?? ''}');
  if (time != null && t != null) {
    d = DateTime(
      d.year,
      d.month,
      d.day,
      int.parse(t[1]!),
      int.parse(t[2]!),
      int.parse(t[3] ?? '0'),
    );
  }
  return d;
}

/// 이름 비교용: 한글·영문·숫자만 남긴다. "홍 길동(청년부)" → "홍길동청년부".
String _norm(String s) =>
    s.replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '').toLowerCase();

/// 입금대기 신청과 입금을 맞춘다. [totals] = 신청 id → 지금 계산 금액(`quote().total`).
///
/// 확실 = 입금자명이 같고 금액이 같고, 그 입금과 그 신청이 서로 하나씩만 맞을 때.
/// 금액이 다르면 '확인 필요'로 차액을 적는다. 입금 확인됐는데 덜 낸 신청은 부족분과 같은 입금을
/// '추가 입금'으로 맞춘다. 신청일 전 입금, 이미 다른 신청의 근거로 쓴 입금(`paid_ref`)은 보지 않는다.
({List<BankMatch> matches, List<BankTx> unmatched}) matchDeposits(
  List<BankTx> txs,
  List<Registration> regs,
  Map<String, int> totals,
) {
  final used = {for (final r in regs) ...paidRefs(r)};
  final fresh = [
    for (final t in txs)
      if (!used.contains(t.ref)) t,
  ];
  final pending = [
    for (final r in regs)
      if (r.status == RegStatus.pending) r,
  ];

  // 0 = 다름, 1 = 비슷(한쪽이 다른 쪽을 품음), 2 = 같음(끝에 붙은 숫자 "홍길동0915" 는 무시)
  int name(BankTx t, Registration r) {
    final want = {
      for (final s in [r.depositorName, r.applicant]) _norm(s),
    }..remove('');
    var best = 0;
    for (final raw in t.texts) {
      final s = _norm(raw);
      if (s.isEmpty) continue;
      for (final w in want) {
        if (s == w || s.replaceFirst(RegExp(r'\d+$'), '') == w) return 2;
        if (s.length >= 2 &&
            w.length >= 2 &&
            (s.contains(w) || w.contains(s))) {
          best = 1;
        }
      }
    }
    return best;
  }

  bool after(BankTx t, Registration r) => !t.at.isBefore(dateOnly(r.createdAt));
  final exact = {
    for (final r in pending)
      r.id: [
        for (final t in fresh)
          if (after(t, r) && t.amount == totals[r.id] && name(t, r) == 2) t,
      ],
  };
  final claims = <BankTx, int>{};
  for (final l in exact.values) {
    for (final t in l) {
      claims[t] = (claims[t] ?? 0) + 1;
    }
  }

  final sure = <BankMatch>[], check = <BankMatch>[];
  for (final r in pending) {
    final total = totals[r.id]!;
    final ex = exact[r.id]!;
    if (ex.length == 1 && claims[ex.first] == 1) {
      sure.add((reg: r, tx: ex.first, due: total, issue: null));
    } else if (ex.length > 1) {
      check.add((
        reg: r,
        tx: ex.first,
        due: total,
        issue: '같은 이름·금액의 입금이 ${ex.length}건',
      ));
    } else if (ex.length == 1) {
      check.add((
        reg: r,
        tx: ex.first,
        due: total,
        issue: '같은 이름·금액의 신청이 ${claims[ex.first]}건',
      ));
    } else {
      final named =
          [
            for (final t in fresh)
              if (after(t, r) && name(t, r) == 2) t,
          ]..sort(
            (a, b) =>
                (a.amount - total).abs().compareTo((b.amount - total).abs()),
          );
      final like = [
        for (final t in fresh)
          if (after(t, r) && t.amount == total && name(t, r) == 1) t,
      ];
      if (named.isNotEmpty) {
        check.add((
          reg: r,
          tx: named.first,
          due: total,
          issue: diffText(named.first.amount, total),
        ));
      } else if (like.isNotEmpty) {
        check.add((reg: r, tx: like.first, due: total, issue: '입금자명이 비슷함'));
      }
    }
  }
  // 입금 확인됐지만 덜 낸 신청: 부족분과 같은 금액을 같은 이름으로 보낸 입금.
  var shown = {
    for (final m in [...sure, ...check]) m.tx,
  };
  for (final r in regs) {
    final short = (totals[r.id] ?? 0) - r.paid;
    if (r.status != RegStatus.confirmed || short <= 0) continue;
    final t = fresh
        .where(
          (t) =>
              !shown.contains(t) &&
              after(t, r) &&
              t.amount == short &&
              name(t, r) == 2,
        )
        .firstOrNull;
    if (t == null) continue;
    check.add((reg: r, tx: t, due: short, issue: '추가 입금 (부족분 ${won(short)})'));
    shown = {...shown, t};
  }
  return (
    matches: [...sure, ...check],
    unmatched: [
      for (final t in fresh)
        if (!shown.contains(t)) t,
    ],
  );
}

// ---------------------------------------------------------------------------
// 파일 형식별 읽기. 결과는 모두 첫 시트의 행 목록(칸 값 = String 또는 num).
// ---------------------------------------------------------------------------

List<List<Object?>> _readCsv(String text) {
  final rows = <List<Object?>>[];
  var row = <Object?>[], cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',' || c == '\t') {
      row.add('$cell');
      cell = StringBuffer();
    } else if (c == '\n') {
      rows.add(row..add('$cell'.replaceAll('\r', '')));
      row = [];
      cell = StringBuffer();
    } else {
      cell.write(c);
    }
  }
  return rows..add(row..add('$cell'));
}

/// 일부 은행의 `.xls` 는 속이 HTML 표다.
List<List<Object?>> _readHtml(String html) {
  String clean(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
  return [
    for (final tr in RegExp(
      r'<tr[\s\S]*?</tr>',
      caseSensitive: false,
    ).allMatches(html))
      [
        for (final td in RegExp(
          r'<t[dh][^>]*>([\s\S]*?)</t[dh]>',
          caseSensitive: false,
        ).allMatches(tr[0]!))
          clean(td[1]!),
      ],
  ];
}

List<List<Object?>> _readXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  XmlDocument? doc(String name) {
    final f = zip.findFile(name);
    return f == null ? null : XmlDocument.parse(utf8.decode(f.readBytes()!));
  }

  // 글자는 <t> 를 모두 이은 것. 후리가나(<rPh>) 안의 <t> 는 뺀다.
  String text(XmlElement e) => [
    for (final t in e.findAllElements('t'))
      if (t.ancestors.whereType<XmlElement>().every(
        (a) => a.name.local != 'rPh',
      ))
        t.innerText,
  ].join();
  final shared = [
    for (final si
        in doc('xl/sharedStrings.xml')?.findAllElements('si') ?? <XmlElement>[])
      text(si),
  ];
  final sheets =
      [
        for (final f in zip.files)
          if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) f.name,
      ]..sort(
        (a, b) => a.length != b.length ? a.length - b.length : a.compareTo(b),
      );
  if (sheets.isEmpty) throw const FormatException('엑셀 파일에 시트가 없습니다.');

  final rows = <List<Object?>>[];
  for (final row in doc(sheets.first)!.findAllElements('row')) {
    final cells = <Object?>[];
    for (final c in row.findElements('c')) {
      final col = _colIndex(c.getAttribute('r'));
      final v = c.getElement('v')?.innerText;
      final Object? value = switch (c.getAttribute('t')) {
        's' => v == null ? null : shared[int.parse(v)],
        'inlineStr' =>
          c.getElement('is') == null ? null : text(c.getElement('is')!),
        'str' || 'b' || 'e' => v,
        _ => v == null ? null : num.tryParse(v) ?? v,
      };
      final at = col ?? cells.length;
      while (cells.length <= at) {
        cells.add(null);
      }
      cells[at] = value;
    }
    rows.add(cells);
  }
  return rows;
}

int? _colIndex(String? ref) {
  final m = RegExp(r'^[A-Z]+').firstMatch(ref ?? '');
  if (m == null) return null;
  return m[0]!.codeUnits.fold<int>(0, (n, c) => n * 26 + c - 64) - 1;
}

/// 옛 엑셀(.xls, BIFF8). 농협 인터넷뱅킹이 이 형식으로 내려준다.
/// 복합 문서(OLE) 안의 'Workbook' 스트림을 꺼내 첫 시트의 칸만 읽는다 — 서식·수식 계산은 안 본다.
List<List<Object?>> _readXls(Uint8List b) {
  final bd = ByteData.sublistView(b);
  int u16(int o) => bd.getUint16(o, Endian.little);
  int u32(int o) => bd.getUint32(o, Endian.little);
  const end = 0xFFFFFFFE;

  final secSize = 1 << u16(0x1E), miniSize = 1 << u16(0x20);
  int sec(int id) => (id + 1) * secSize;
  // FAT 섹터 목록: 머리의 109칸 + DIFAT 사슬.
  final fatSecs = <int>[for (var i = 0; i < 109; i++) u32(0x4C + i * 4)];
  for (var d = u32(0x44), n = u32(0x48); n > 0 && d < end; n--) {
    final o = sec(d);
    for (var i = 0; i < secSize ~/ 4 - 1; i++) {
      fatSecs.add(u32(o + i * 4));
    }
    d = u32(o + secSize - 4);
  }
  final fat = <int>[
    for (final s in fatSecs.take(u32(0x2C)))
      for (var i = 0; i < secSize ~/ 4; i++) u32(sec(s) + i * 4),
  ];
  Uint8List chain(
    int start,
    List<int> table,
    int Function(int) offset,
    int size,
  ) {
    final out = BytesBuilder(copy: false);
    for (
      var s = start, guard = 0;
      s < end && s < table.length && guard < table.length;
      guard++
    ) {
      final o = offset(s);
      out.add(Uint8List.sublistView(b, o, (o + size).clamp(0, b.length)));
      s = table[s];
    }
    return out.takeBytes();
  }

  final dir = chain(u32(0x30), fat, sec, secSize);
  final dd = ByteData.sublistView(dir);
  ({int start, int size})? root, book;
  for (var o = 0; o + 128 <= dir.length; o += 128) {
    final len = dd.getUint16(o + 64, Endian.little);
    if (len < 2) continue;
    final name = String.fromCharCodes([
      for (var i = 0; i < len - 2; i += 2) dd.getUint16(o + i, Endian.little),
    ]);
    final e = (
      start: dd.getUint32(o + 116, Endian.little),
      size: dd.getUint32(o + 120, Endian.little),
    );
    if (dir[o + 66] == 5) root = e;
    if (name == 'Workbook' || name == 'Book') book = e;
  }
  if (book == null || root == null) {
    throw const FormatException('엑셀 파일을 읽지 못했습니다.');
  }

  Uint8List stream;
  if (book.size < u32(0x38)) {
    // 작은 스트림은 미니 스트림(루트 항목의 사슬) 안에 64바이트 단위로 들어 있다.
    final miniFatBytes = chain(u32(0x3C), fat, sec, secSize);
    final mfd = ByteData.sublistView(miniFatBytes);
    final miniFat = [
      for (var i = 0; i + 4 <= miniFatBytes.length; i += 4)
        mfd.getUint32(i, Endian.little),
    ];
    final mini = chain(root.start, fat, sec, secSize);
    final out = BytesBuilder(copy: false);
    for (
      var s = book.start, guard = 0;
      s < end && s < miniFat.length && guard < miniFat.length;
      guard++
    ) {
      final o = s * miniSize;
      out.add(
        Uint8List.sublistView(mini, o, (o + miniSize).clamp(0, mini.length)),
      );
      s = miniFat[s];
    }
    stream = out.takeBytes();
  } else {
    stream = chain(book.start, fat, sec, secSize);
  }
  return _readBiff(
    Uint8List.sublistView(stream, 0, book.size.clamp(0, stream.length)),
  );
}

List<List<Object?>> _readBiff(Uint8List s) {
  final d = ByteData.sublistView(s);
  // 레코드: [종류 2][길이 2][내용]
  final recs = <(int, Uint8List)>[];
  for (var o = 0; o + 4 <= s.length;) {
    final type = d.getUint16(o, Endian.little),
        len = d.getUint16(o + 2, Endian.little);
    recs.add((
      type,
      Uint8List.sublistView(s, o + 4, (o + 4 + len).clamp(0, s.length)),
    ));
    o += 4 + len;
  }
  if (recs.isEmpty || recs.first.$1 != 0x0809) {
    throw const FormatException('엑셀 파일을 읽지 못했습니다.');
  }

  final sst = <String>[];
  final cells = <int, Map<int, Object?>>{};
  var bof = 0;
  for (var i = 0; i < recs.length; i++) {
    final (type, data) = recs[i];
    final rd = ByteData.sublistView(data);
    int r16(int o) => rd.getUint16(o, Endian.little);
    void put(int row, int col, Object? v) => (cells[row] ??= {})[col] = v;
    switch (type) {
      case 0x0809: // BOF — 1 = 통합문서 앞부분, 2 = 첫 시트
        bof++;
      case 0x000A when bof >= 2: // 첫 시트의 EOF
        i = recs.length;
      case 0x00FC: // SST 공유 글자표 (+ 뒤따르는 CONTINUE)
        final segs = [data];
        while (i + 1 < recs.length && recs[i + 1].$1 == 0x003C) {
          segs.add(recs[++i].$2);
        }
        sst.addAll(_readSst(segs));
      case 0x00FD when bof >= 2: // LABELSST
        final k = rd.getUint32(6, Endian.little);
        put(r16(0), r16(2), k < sst.length ? sst[k] : null);
      case 0x0204 when bof >= 2: // LABEL
        put(r16(0), r16(2), (_BiffReader([data])..pos = 6).str16());
      case 0x0203 when bof >= 2: // NUMBER
        put(r16(0), r16(2), rd.getFloat64(6, Endian.little));
      case 0x027E when bof >= 2: // RK
        put(r16(0), r16(2), _rk(rd.getUint32(6, Endian.little)));
      case 0x00BD when bof >= 2: // MULRK
        final n = (data.length - 6) ~/ 6;
        for (var k = 0; k < n; k++) {
          put(
            r16(0),
            r16(2) + k,
            _rk(rd.getUint32(4 + k * 6 + 2, Endian.little)),
          );
        }
      case 0x0006
          when bof >= 2: // FORMULA — 숫자 결과만. 글자 결과는 바로 뒤 STRING 레코드에 있다.
        if (r16(12) != 0xFFFF) {
          put(r16(0), r16(2), rd.getFloat64(6, Endian.little));
        } else if (data[6] == 0 &&
            i + 1 < recs.length &&
            recs[i + 1].$1 == 0x0207) {
          put(r16(0), r16(2), (_BiffReader([recs[++i].$2])).str16());
        }
    }
  }
  if (cells.isEmpty) return [];
  final last = cells.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (var r = 0; r <= last; r++)
      if (cells[r] case final row?)
        [
          for (var c = 0; c <= row.keys.reduce((a, b) => a > b ? a : b); c++)
            row[c],
        ]
      else
        <Object?>[],
  ];
}

num _rk(int rk) {
  final num v;
  if (rk & 2 != 0) {
    v = rk.toSigned(32) >> 2;
  } else {
    final bd = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
    v = bd.getFloat64(0, Endian.little);
  }
  return rk & 1 != 0 ? v / 100 : v;
}

List<String> _readSst(List<Uint8List> segs) {
  final r = _BiffReader(segs);
  final count = (r..pos = 4).u32(); // [총 개수 4][고유 개수 4]
  return [for (var k = 0; k < count && !r.done; k++) r.str16()];
}

/// SST 처럼 CONTINUE 레코드로 잘린 내용을 이어서 읽는다.
/// 글자 중간에 잘리면 새 조각 첫 바이트가 그 뒤 글자의 폭(1 = UTF-16, 0 = 1바이트)이다.
class _BiffReader {
  _BiffReader(this.segs);
  final List<Uint8List> segs;
  int seg = 0, pos = 0;

  bool get done =>
      seg >= segs.length || (seg == segs.length - 1 && pos >= segs[seg].length);

  int u8() {
    while (pos >= segs[seg].length) {
      seg++;
      pos = 0;
    }
    return segs[seg][pos++];
  }

  int u16() => u8() | u8() << 8;
  int u32() => u16() | u16() << 16;

  /// BIFF8 유니코드 문자열: [글자 수 2][옵션 1][서식 수 2]?[확장 길이 4]?[글자][서식][확장]
  String str16() {
    final n = u16(), flags = u8();
    final runs = flags & 8 != 0 ? u16() : 0;
    final ext = flags & 4 != 0 ? u32() : 0;
    var wide = flags & 1 != 0;
    final out = StringBuffer();
    for (var k = 0; k < n; k++) {
      if (pos >= segs[seg].length) {
        seg++;
        pos = 0;
        wide = segs[seg][pos++] & 1 != 0;
      }
      out.writeCharCode(wide ? u16() : u8());
    }
    for (var k = 0; k < runs * 4 + ext; k++) {
      u8();
    }
    return '$out';
  }
}
