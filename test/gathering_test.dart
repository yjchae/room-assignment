// 집회·신청 모델, 이미지 줄이기, 신청 → 참석자 가져오기.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:room_assignment/auto_assign.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final start = DateTime(2026, 10, 9);
final end = DateTime(2026, 10, 11);

Gathering sample() => Gathering(
  id: 'g1',
  name: '가족수양회',
  start: start,
  end: end,
  themes: ['영혼육', '다음세대'],
  place: '수양관',
  bank: Bank(bank: '국민', account: '000-00-0000', holder: '교회'),
  formFields: ['교회'],
  open: true,
  deadline: DateTime(2026, 9, 30),
  fee: FeeRule(
    full: {AgeGroup.adult: 150000, AgeGroup.youth: 120000},
    perNight: {AgeGroup.adult: 70000, AgeGroup.kinder: 30000},
    dayOnly: {AgeGroup.adult: 30000},
    minAge: {...FeeRule.defaultMinAge, AgeGroup.adult: 20},
    perRegistration: 10000,
    fullDiscountPct: 5,
    early: [(fromDays: 38, toDays: 19, pct: 10)],
  ),
);

Person person(
  String name,
  int birthYear, {
  String gender = 'M',
  DateTime? checkIn,
  DateTime? checkOut,
  Map<String, String>? extra,
}) => Person(
  id: 'p-$name',
  name: name,
  gender: gender,
  birthYear: birthYear,
  checkIn: checkIn,
  checkOut: checkOut,
  extra: extra,
);

Registration reg(String id, RegStatus status, List<Person> people) =>
    Registration(
      id: id,
      gatheringId: 'g1',
      phone: '01012345678',
      people: people,
      status: status,
      createdAt: DateTime(2026, 9, 10),
    );

/// 홈스테이 신청 한 건. [capacity] 는 신청서의 '수용 인원' 항목 값.
Registration homeReg(
  String id,
  String name, {
  String? capacity,
  RegStatus status = RegStatus.confirmed,
}) => Registration(
  id: id,
  gatheringId: 'h1',
  phone: '0101111${id.padLeft(4, '0')}',
  people: [
    Person(
      id: 'p-$id',
      name: name,
      gender: 'M',
      birthYear: 1980,
      extra: {homestayCapacityField: ?capacity},
    ),
  ],
  status: status,
  createdAt: DateTime(2026, 9, 10),
);

Gathering homestay() => Gathering(
  id: 'h1',
  name: '홈스테이',
  kind: GatheringKind.homestay,
  start: start,
  end: end,
  formFields: [homestayCapacityField],
);

/// 집회를 열지 않은 Store — 서버에 저장하지 않는다.
Store tmpStore() =>
    Store()..event = Event(name: 'x', startDate: start, endDate: end);

void main() {
  group('모델', () {
    test('Gathering 은 서버 행(JSON)을 거쳐도 그대로다 — 금액까지', () {
      final g = sample();
      final back = Gathering.fromRow({...g.toRow(), 'id': g.id});
      expect(back.id, 'g1');
      expect(back.name, g.name);
      expect(back.themes, g.themes);
      expect(back.bank.account, '000-00-0000');
      expect(back.deadline, DateTime(2026, 9, 30));
      expect(back.formFields, ['교회']);
      expect(back.fee.minAge[AgeGroup.adult], 20);
      expect(back.fee.early.single, (fromDays: 38, toDays: 19, pct: 10));
      final family = [
        person('아빠', 1985),
        person('딸', 2012),
        person('막내', 2021, checkIn: DateTime(2026, 10, 10)),
      ];
      final on = DateTime(2026, 9, 10);
      expect(back.quoteFor(family, on).total, g.quoteFor(family, on).total);
      expect(g.quoteFor(family, on).total, greaterThan(0));
    });

    test('사역자 안내는 사역자를 체크한 신청에만, 설정이 켜져 있을 때만', () {
      final g = sample();
      final minister = Person.fromJson({
        ...person('목사', 1970).toJson(),
        'minister': true,
      });
      expect(minister.minister, isTrue);
      expect(g.ministerNotice, Gathering.defaultMinisterNotice);
      expect(g.ministerNoticeFor([person('a', 1990)]), isFalse);
      expect(g.ministerNoticeFor([person('a', 1990), minister]), isTrue);

      g
        ..ministerNoticeOn = false
        ..ministerNotice = '문의: 총무';
      final back = Gathering.fromRow({...g.toRow(), 'id': 'x'});
      expect(back.ministerNotice, '문의: 총무');
      expect(back.ministerNoticeFor([minister]), isFalse);

      g
        ..ministerNoticeOn = true
        ..hiddenFields.add('minister');
      expect(g.ministerNoticeFor([minister]), isFalse); // 체크 칸을 안 받으면 안 보인다
    });

    test('모르는 값·빈 값은 기본값으로 읽는다', () {
      final g = Gathering.fromRow({
        'id': 'x',
        'name': 'n',
        'start_date': '2026-01-01',
        'end_date': '2026-01-03',
        'fee': {
          'full': {'adult': 1000, 'alien': 5},
          'early': ['bad'],
        },
      });
      expect(g.fee.full, {AgeGroup.adult: 1000});
      expect(g.fee.early, isEmpty);
      expect(g.fee.minAge, FeeRule.defaultMinAge);
      expect(g.bank.isEmpty, isTrue);
      expect(g.open, isFalse);
    });

    test('Registration: 조회 함수가 돌려준 jsonb 를 읽는다', () {
      final r = Registration.fromRow({
        'id': 'r1',
        'gathering_id': 'g1',
        'phone': '01012345678',
        'people': [
          person('아빠', 1985, checkIn: DateTime(2026, 10, 10)).toJson(),
          person('딸', 2012, gender: 'F', extra: {'교회': '신촌'}).toJson(),
        ],
        'quoted': 415000,
        'status': 'confirmed',
        'paid': 415000,
        'paid_at': '2026-09-11',
        'created_at': '2026-09-10T03:00:00+00:00',
      });
      expect(r.status, RegStatus.confirmed);
      expect(r.applicant, '아빠');
      expect(r.depositorName, '아빠');
      expect(r.people[0].checkIn, DateTime(2026, 10, 10));
      expect(r.people[1].gender, 'F');
      expect(r.people[1].extra, {'교회': '신촌'});
      expect(r.paidAt, DateTime(2026, 9, 11));
      expect(r.createdAt.isUtc, isFalse); // 한국 시간으로 보여준다
      expect(r.createdAt, DateTime.utc(2026, 9, 10, 3).toLocal());
    });

    test('신청 받는 중: 마감일 당일까지', () {
      final g = sample();
      expect(g.acceptingOn(DateTime(2026, 9, 30, 23, 59)), isTrue);
      expect(g.acceptingOn(DateTime(2026, 10, 1)), isFalse);
      expect((g..open = false).acceptingOn(DateTime(2026, 9, 1)), isFalse);
      expect(
        (sample()..deadline = null).acceptingOn(DateTime(2030, 1, 1)),
        isTrue,
      );
    });

    test('집회 날짜 목록과 표시 도우미', () {
      expect(sample().days, [
        DateTime(2026, 10, 9),
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 11),
      ]);
      expect(won(415000), '415,000원');
      expect(won(0), '0원');
      expect(won(-1500), '-1,500원');
      expect(fmtPhone('01012345678'), '010-1234-5678');
      expect(fmtPhone('010-123-4567'), '010-123-4567');
      expect(validPhone('010-1234-5678'), isTrue);
      expect(validPhone('02-123-4567'), isFalse);
      expect(mdw(DateTime(2026, 10, 9)), '10-09(금)');
      expect(stayLabel(2), '2박3일');
      expect(stayLabel(0), '당일');
    });

    test('서버 에러 → 안내 문장', () {
      expect(
        errorText(const PostgrestException(message: 'ALREADY_REGISTERED')),
        contains('이미 신청'),
      );
      expect(
        errorText(const PostgrestException(message: 'TOO_MANY_ATTEMPTS')),
        contains('30분'),
      );
      expect(errorText(const RemoteError('그대로')), '그대로');
      expect(
        errorText(Exception('ClientException: Failed host lookup')),
        contains('인터넷'),
      );
    });
  });

  group('이미지 줄이기', () {
    /// 사진 비슷한 그림: 부드러운 그라데이션 + 약한 잡음.
    Uint8List photo(int w, int h, {int noise = 12, int seed = 1}) {
      final r = Random(seed);
      final im = img.Image(width: w, height: h);
      for (final p in im) {
        int c(int base) =>
            (base + r.nextInt(noise * 2 + 1) - noise).clamp(0, 255);
        p
          ..r = c(p.x * 255 ~/ w)
          ..g = c(p.y * 255 ~/ h)
          ..b = c(128);
      }
      return img.encodePng(im);
    }

    test('포스터: 큰 사진을 가로 900px · 250KB 이하 JPEG 로', () {
      final out = shrinkImage(photo(2000, 2800), ImageKind.poster)!;
      final back = img.decodeJpg(out)!;
      expect(back.width, 900);
      expect(back.height, 1260); // 비율 유지
      expect(out.length, lessThanOrEqualTo(ImageKind.poster.maxBytes));
    });

    test('배경: 가로 960px · 80KB 이하', () {
      final out = shrinkImage(photo(3000, 1700), ImageKind.background)!;
      expect(img.decodeJpg(out)!.width, 960);
      expect(out.length, lessThanOrEqualTo(ImageKind.background.maxBytes));
    });

    test('잡음뿐인 최악의 사진도 서버 한도(1MB)는 넘지 않는다', () {
      final out = shrinkImage(photo(1800, 2400, noise: 127), ImageKind.poster)!;
      expect(out.length, lessThan(1024 * 1024));
    });

    test('작은 사진은 키우지 않는다', () {
      final out = shrinkImage(photo(400, 300), ImageKind.poster)!;
      expect(img.decodeJpg(out)!.width, 400);
    });

    test('투명 PNG 는 흰 바탕에 얹는다 (검게 나오지 않게)', () {
      final im = img.Image(width: 50, height: 50, numChannels: 4); // 전부 투명
      final out = shrinkImage(img.encodePng(im), ImageKind.poster)!;
      final p = img.decodeJpg(out)!.getPixel(25, 25);
      expect([p.r, p.g, p.b].every((c) => c > 240), isTrue, reason: '$p');
    });

    test('이미지가 아니면 null', () {
      expect(
        shrinkImage(Uint8List.fromList([1, 2, 3]), ImageKind.poster),
        isNull,
      );
    });
  });

  group('신청 → 참석자 가져오기', () {
    final g = sample()..fee = FeeRule();

    test('확정된 신청만 가져오고, 전화·나이·일정을 채운다', () {
      final s = tmpStore();
      final r = s.syncRegistrations(g, [
        reg('r1', RegStatus.confirmed, [
          person('아빠', 1985),
          person('딸', 2012, gender: 'F', checkIn: DateTime(2026, 10, 10)),
        ]),
        reg('r2', RegStatus.pending, [person('대기', 1990)]),
        reg('r3', RegStatus.cancelled, [person('취소', 1990)]),
      ]);
      expect((r.added, r.updated, r.removed, r.dayOnly), (2, 0, 0, 0));
      final dad = s.event.attendees.firstWhere((a) => a.name == '아빠');
      final kid = s.event.attendees.firstWhere((a) => a.name == '딸');
      expect(dad.id, 'p-아빠');
      expect(dad.registrationId, 'r1');
      expect(dad.age, 41);
      expect(dad.phone, '010-1234-5678');
      expect((dad.checkIn, dad.checkOut), (start, end));
      expect(kid.gender, 'F');
      expect(kid.phone, '010-1234-5678'); // 동반자는 신청자 번호
      expect(kid.checkIn, DateTime(2026, 10, 10));
    });

    test('몇 번 불러도 같다', () {
      final s = tmpStore();
      final regs = [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985)]),
      ];
      s.syncRegistrations(g, regs);
      final again = s.syncRegistrations(g, regs);
      expect((again.added, again.updated, again.removed), (0, 0, 0));
      expect(s.event.attendees, hasLength(1));
    });

    test('remove: false 면 추가·수정만 하고 빼지는 않는다 (입금 확인 때 자동 등록)', () {
      final s = tmpStore();
      final r1 = reg('r1', RegStatus.confirmed, [person('아빠', 1985)]);
      s.syncRegistrations(g, [r1]);
      s.event.attendees.single.roomId = 'room301';
      r1.status = RegStatus.cancelled;
      final r2 = reg('r2', RegStatus.confirmed, [person('새가족', 1990)]);
      final res = s.syncRegistrations(g, [r1, r2], remove: false);
      expect((res.added, res.removed), (1, 0));
      expect(s.event.attendees.map((a) => a.name), ['아빠', '새가족']);
      expect(s.event.attendees.first.roomId, 'room301'); // 방 배정이 말없이 풀리지 않는다
    });

    test('바뀐 내용은 덮어쓰되 배정된 방·기타는 그대로', () {
      final s = tmpStore();
      final p = person('아빠', 1985);
      final regs = [
        reg('r1', RegStatus.confirmed, [p]),
      ];
      s.syncRegistrations(g, regs);
      s.event.attendees.single
        ..roomId = 'room301'
        ..note = '강사';
      p
        ..name = '아버지'
        ..checkIn = DateTime(2026, 10, 10);
      final r = s.syncRegistrations(g, regs);
      expect(r.updated, 1);
      final a = s.event.attendees.single;
      expect(a.name, '아버지');
      expect(a.checkIn, DateTime(2026, 10, 10));
      expect(a.roomId, 'room301');
      expect(a.note, '강사');
    });

    test('운영자가 고치거나 지운 사람은 먼저 알려주고, 고른 쪽으로 맞춘다', () {
      final s = tmpStore();
      final regs = [
        reg('r1', RegStatus.confirmed, [
          person('아빠', 1985),
          person('엄마', 1987, gender: 'F'),
        ]),
      ];
      s.syncRegistrations(g, regs);
      s.event.attendees.firstWhere((a) => a.name == '아빠')
        ..name = '아빠(수정)'
        ..editedByAdmin = true;
      s.deleteAttendees(s.event.attendees.where((a) => a.name == '엄마'));

      final c = s.syncConflicts(g, regs);
      expect(c.edited.map((a) => a.name), ['아빠(수정)']);
      expect(c.deleted.map((a) => a.name), ['엄마']);

      // 운영자 수정 유지 (기본값 — 입금 확인 때 자동으로 부를 때도 이쪽)
      s.syncRegistrations(g, regs);
      expect(s.event.attendees.map((a) => a.name), ['아빠(수정)']);

      // 신청 내용으로
      s.syncRegistrations(g, regs, keepAdminEdits: false);
      expect(
        s.event.attendees.map((a) => a.name),
        unorderedEquals(['아빠', '엄마']),
      );
      final after = s.syncConflicts(g, regs);
      expect(after.edited, isEmpty);
      expect(after.deleted, isEmpty);

      // 지운 기록은 JSON 에도 남는다 (다른 기기에서 가져오기를 눌러도 같게)
      s.deleteAttendees(s.event.attendees.where((a) => a.name == '엄마'));
      expect(Event.fromJson(s.event.toJson()).deletedIds, {'p-엄마'});
    });

    test('취소되면 빠진다 — 방이 배정된 사람은 먼저 알려준다', () {
      final s = tmpStore();
      final r1 = reg('r1', RegStatus.confirmed, [
        person('아빠', 1985),
        person('엄마', 1987, gender: 'F'),
      ]);
      s.syncRegistrations(g, [r1]);
      s.event.attendees.first.roomId = 'room301';
      r1.status = RegStatus.cancelled;
      expect(s.syncWouldRemove(g, [r1]).map((a) => a.name), ['아빠']);
      expect(s.syncRegistrations(g, [r1]).removed, 2);
      expect(s.event.attendees, isEmpty);
    });

    test('붙여넣기로 등록한 사람은 건드리지 않는다', () {
      final s = tmpStore();
      s.event.attendees.add(
        Attendee(
          id: 'paste1',
          name: '현장등록',
          gender: 'M',
          age: 30,
          checkIn: start,
          checkOut: end,
        ),
      );
      s.syncRegistrations(g, []);
      expect(s.event.attendees.single.id, 'paste1');
    });

    test('날짜를 띄엄띄엄 고르면 묵는 밤만 정원에 센다', () {
      final s = tmpStore();
      final g4 = sample()
        ..fee = FeeRule()
        ..end = DateTime(2026, 10, 13);
      final d = [9, 10, 12, 13].map((x) => DateTime(2026, 10, x)).toList();
      s.syncRegistrations(g4, [
        reg('r1', RegStatus.confirmed, [
          Person(id: 'p1', name: '띄엄', gender: 'M', birthYear: 1990, days: d),
        ]),
      ]);
      final a = s.event.attendees.single;
      expect((a.checkIn, a.checkOut), (d[0], d[3]));
      expect(a.staysOn(DateTime(2026, 10, 9)), isTrue);
      expect(a.staysOn(DateTime(2026, 10, 11)), isFalse); // 빠진 밤
      expect(a.staysOn(DateTime(2026, 10, 12)), isTrue);
      final back = Attendee.fromJson(a.toJson());
      expect(back.stayNights, a.stayNights);
    });

    test('과거 집회 복사: 고른 것만, 배정·신청 연결은 풀고 나이는 해가 바뀐 만큼', () {
      final src = Event(
        name: '작년',
        startDate: DateTime(2025, 10, 9),
        endDate: DateTime(2025, 10, 11),
        rooms: [Room(id: 'r1', roomNo: '301', capacity: 4)],
        attendees: [
          Attendee(
            id: 'a',
            name: '홍',
            gender: 'M',
            age: 40,
            roomId: 'r1',
            registrationId: 'x',
            checkIn: DateTime(2025, 10, 10),
            checkOut: DateTime(2025, 10, 11),
          ),
        ],
        customFields: ['교회'],
      );
      final e = copyEvent(
        src,
        name: '올해',
        start: start,
        end: end,
        rooms: true,
        attendees: true,
      );
      expect(e.rooms.single.roomNo, '301');
      final a = e.attendees.single;
      expect((a.roomId, a.registrationId, a.age), (null, null, 41));
      expect((a.checkIn, a.checkOut), (start, end));
      expect(e.customFields, ['교회']);
      final roomsOnly = copyEvent(
        src,
        name: 'x',
        start: start,
        end: end,
        rooms: true,
      );
      expect(roomsOnly.attendees, isEmpty);
      expect(src.attendees.single.roomId, 'r1'); // 원본은 그대로
    });

    test('참석자 CSV: 방·일정이 들어가고, 쉼표·따옴표는 감싸고, 수식은 막는다', () {
      final e = Event(
        name: 'x',
        startDate: start,
        endDate: end,
        rooms: [Room(id: 'r1', roomNo: '301', building: '반석관', capacity: 4)],
        attendees: [
          Attendee(
            id: 'a',
            name: '홍, "길동"',
            gender: 'F',
            age: 30,
            roomId: 'r1',
            checkIn: start,
            checkOut: end,
            extra: {'교회': '=1+1'},
          ),
        ],
        customFields: ['교회'],
      );
      final lines = attendeesCsv(e).split('\r\n');
      expect(lines[0], '이름,성별,나이,전화,셀,존,기타,교회,방,체크인,체크아웃');
      expect(
        lines[1],
        '"홍, ""길동""",여,30,,,,,\'=1+1,반석관 301,2026-10-09,2026-10-11',
      );
    });

    test('당일 참석자는 방이 필요 없어 뺀다', () {
      final s = tmpStore();
      final day = DateTime(2026, 10, 10);
      final r = s.syncRegistrations(g, [
        reg('r1', RegStatus.confirmed, [
          person('자는사람', 1985),
          person('당일', 1990, checkIn: day, checkOut: day),
        ]),
      ]);
      expect((r.added, r.dayOnly), (1, 1));
    });

    test('신청서의 추가 항목이 참석자 항목으로 생긴다', () {
      final s = tmpStore();
      s.syncRegistrations(g, [
        reg('r1', RegStatus.confirmed, [
          person('아빠', 1985, extra: {'직분': '집사'}),
        ]),
      ]);
      expect(s.event.customFields, contains('직분'));
      expect(s.event.attendees.single.extra, {'직분': '집사'});
    });

    test('집회 설정을 방배정 파일에 반영한다', () {
      final s = tmpStore();
      s.applyGathering(
        Gathering(
          id: 'g1',
          name: '새 이름',
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 1), // 당일 행사여도 방배정은 최소 1박
          formFields: ['교회', '이름'], // 기본 항목과 겹치는 이름은 무시
        ),
      );
      expect(s.event.name, '새 이름');
      expect(s.event.startDate, DateTime(2026, 11, 1));
      expect(s.event.endDate, DateTime(2026, 11, 2));
      expect(s.event.customFields, ['교회']);
    });

    test('자동배정 "가족" 기준: 같은 신청이면 같은 그룹', () {
      Attendee a(String id, String? regId) => Attendee(
        id: id,
        name: id,
        gender: 'M',
        age: 30,
        checkIn: start,
        checkOut: end,
        registrationId: regId,
      );
      final rule = AutoRule(groupBy: [GroupField.family]);
      expect(rule.keyOf(a('1', 'r1')), rule.keyOf(a('2', 'r1')));
      expect(rule.keyOf(a('1', 'r1')), isNot(rule.keyOf(a('3', 'r2'))));
      expect(rule.keyOf(a('4', null)), isNull);
      expect(GroupField.builtins, contains(GroupField.family));
    });

    test('registrationId 는 방배정 문서(JSON)에 남는다', () {
      final s = tmpStore();
      s.syncRegistrations(g, [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985)]),
      ]);
      final back = Event.fromJson(s.event.toJson());
      expect(back.attendees.single.registrationId, 'r1');
    });
  });

  test('존은 소문자로 넣어도 대문자로 담긴다 (신청서·참석자·저장된 JSON)', () {
    expect(
      Person(name: 'x', gender: 'M', birthYear: 1990, zone: 'a존').zone,
      'A존',
    );
    expect(Person.fromJson({'name': 'x', 'zone': 'b'}).zone, 'B');
    final a = Attendee.fromJson({
      'id': '1',
      'name': 'x',
      'gender': 'M',
      'age': 30,
      'zone': 'c존',
      'checkIn': '2026-01-01T00:00:00.000',
      'checkOut': '2026-01-02T00:00:00.000',
    });
    expect(a.zone, 'C존');
    a.zone = 'd';
    expect(a.zone, 'D');
    expect(a.toJson()['zone'], 'D');
  });

  group('일정표', () {
    test('서버 행(JSON)을 거쳐도 그대로고, 날짜별로 시간 순으로 읽힌다', () {
      final g = sample()
        ..schedule = [
          (date: DateTime(2026, 10, 10), time: '09:00', title: '아침기도'),
          (date: start, time: '21:00', title: '조모임'),
          (date: start, time: '19:30', title: '개회예배'),
          (date: DateTime(2026, 12, 25), time: '', title: '기간 밖'),
        ];
      final back = Gathering.fromRow({...g.toRow(), 'id': g.id});
      expect(back.schedule, hasLength(4));
      expect(
        back.scheduleOn(start).map((e) => e.title),
        ['개회예배', '조모임'], // 시간 순
      );
      expect(back.scheduleOn(DateTime(2026, 10, 11)), isEmpty);
      expect(back.hasSchedule, isTrue);
      // 기간 밖 항목은 어느 날짜에도 안 뜨지만 저장은 돼 있다.
      expect(back.days.any((d) => back.scheduleOn(d).length == 1), isTrue);
      expect(sample().hasSchedule, isFalse);
    });
  });

  group('집회 구분', () {
    test('구분은 서버 행을 거쳐도 그대로, 모르는 값은 집회로 읽는다', () {
      final h = homestay();
      expect(Gathering.fromRow({...h.toRow(), 'id': 'h1'}).isHomestay, isTrue);
      expect(h.copy().kind, GatheringKind.homestay);
      expect(sample().toRow()['kind'], 'gathering');
      expect(Gathering.fromRow({'name': 'x', 'kind': '엉뚱'}).isHomestay, isFalse);
    });
  });

  // 홈스테이를 넣느라 공용 코드(Attendee·Store·신청 가져오기)를 건드렸다.
  // 일반 집회가 그대로인지 여기서 못 박는다.
  group('일반 집회: 홈스테이 변경의 사이드 이펙트 없음', () {
    final g = sample()..fee = FeeRule();

    test('신청 가져오기는 예전 그대로다 (방·기타는 유지, 취소는 제거)', () {
      final s = tmpStore();
      final regs = [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985), person('딸', 2012)]),
      ];
      s.syncRegistrations(g, regs);
      final dad = s.event.attendees.firstWhere((a) => a.name == '아빠');
      dad
        ..roomId = '301'
        ..note = '알레르기';
      // 다시 불러도 방·기타는 그대로, 사람도 그대로
      final again = s.syncRegistrations(g, regs);
      expect((again.added, again.updated, again.removed), (0, 0, 0));
      expect((dad.roomId, dad.note), ('301', '알레르기'));
      expect(dad.splitOf, isNull); // 새 칸은 기본이 null
      expect(s.event.rooms, isEmpty); // 일반 집회는 방이 저절로 생기지 않는다

      // 취소하면 빠진다
      regs[0].status = RegStatus.cancelled;
      expect(s.syncRegistrations(g, regs).removed, 2);
    });

    test('신청 취소·삭제는 참석자만 뺀다 (방은 건드리지 않는다)', () {
      final s = tmpStore();
      s.event.rooms.add(Room(id: 'R', roomNo: '301', capacity: 4));
      s.syncRegistrations(g, [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985)]),
      ]);
      s.event.attendees.single.roomId = 'R';
      expect(s.wouldLoseRoom('r1').single.name, '아빠');
      final n = s.removeRegistration('r1');
      expect((n.people, n.rooms), (1, 0)); // 방은 그대로
      expect(s.event.rooms, hasLength(1));
    });

    test('참석자 일정을 운영자가 고치면 가져오기가 되돌리지 않는다', () {
      final s = tmpStore();
      final regs = [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985)]),
      ];
      s.syncRegistrations(g, regs);
      final dad = s.event.attendees.single;
      dad
        ..checkOut = DateTime(2026, 10, 10)
        ..editedByAdmin = true; // 참석자 수정 창이 하는 일
      expect(s.syncConflicts(g, regs).edited.single.id, dad.id);
      s.syncRegistrations(g, regs); // keepAdminEdits 기본값
      expect(dad.checkOut, DateTime(2026, 10, 10));
      // 운영자 수정을 버리기로 하면 신청 일정으로 돌아온다
      s.syncRegistrations(g, regs, keepAdminEdits: false);
      expect(dad.checkOut, end);
    });

    test('나눈 조각은 신청 가져오기가 지우지 않는다', () {
      final s = tmpStore();
      final regs = [
        reg('r1', RegStatus.confirmed, [person('아빠', 1985)]),
      ];
      s.syncRegistrations(g, regs);
      final dad = s.event.attendees.single;
      final later = s.splitStay(dad, DateTime(2026, 10, 10))!;
      expect(later.registrationId, isNull); // 신청과 끊어 둔다
      s.syncRegistrations(g, regs);
      expect(s.event.attendees, hasLength(2));
      expect(later.checkIn, DateTime(2026, 10, 10));
    });
  });

  group('홈스테이: 신청 → 가정(방)', () {
    final g = homestay();

    test('확정된 신청마다 방이 생긴다 — 이름·정원·연락처', () {
      final s = tmpStore();
      final r = s.syncHomestayRooms(g, [
        homeReg('1', '김호스트', capacity: '3'),
        homeReg('2', '이호스트'), // 수용 인원 없음 → 기본값
        homeReg('3', '대기중', status: RegStatus.pending),
      ]);
      expect((r.added, r.updated, r.removed), (2, 0, 0));
      expect(s.event.rooms, hasLength(2));
      final a = s.event.rooms.firstWhere((x) => x.registrationId == '1');
      expect(a.roomNo, '김호스트');
      expect(a.capacity, 3);
      expect(a.note, '010-1111-0001'); // 보기 좋은 모양으로
      expect(
        s.event.rooms.firstWhere((x) => x.registrationId == '2').capacity,
        defaultHomeCapacity,
      );
    });

    test('몇 번 불러도 같다. 이름은 따라가고 정원은 운영자 것이 이긴다', () {
      final s = tmpStore();
      s.syncHomestayRooms(g, [homeReg('1', '김호스트', capacity: '3')]);
      final again = s.syncHomestayRooms(g, [
        homeReg('1', '김호스트', capacity: '3'),
      ]);
      expect((again.added, again.updated, again.removed), (0, 0, 0));

      s.event.rooms.first.capacity = 9; // 운영자가 고침
      final renamed = s.syncHomestayRooms(g, [
        homeReg('1', '김호스트네', capacity: '3'),
      ]);
      expect((renamed.added, renamed.updated), (0, 1));
      expect(s.event.rooms.first.roomNo, '김호스트네');
      expect(s.event.rooms.first.capacity, 9);
    });

    test('확정이 풀리면 방이 빠지고 배정도 풀린다. remove: false 면 그대로 둔다', () {
      final s = tmpStore();
      s.syncHomestayRooms(g, [homeReg('1', '김호스트')]);
      final room = s.event.rooms.single;
      s.event.attendees.add(
        Attendee(
          id: 'a1',
          name: '손님',
          gender: 'M',
          age: 30,
          checkIn: start,
          checkOut: end,
          roomId: room.id,
        ),
      );

      final pending = [homeReg('1', '김호스트', status: RegStatus.pending)];
      expect(s.homestayWouldRemove(g, pending).single.roomNo, '김호스트');
      s.syncHomestayRooms(g, pending, remove: false);
      expect(s.event.rooms, hasLength(1));

      final r = s.syncHomestayRooms(g, pending);
      expect(r.removed, 1);
      expect(s.event.rooms, isEmpty);
      expect(s.event.attendees.single.roomId, isNull); // 손님은 미배정으로
    });

    test('신청을 취소·삭제하면 그 가정이 방배정에서 빠진다', () {
      final s = tmpStore();
      s.syncHomestayRooms(g, [homeReg('1', '김호스트')]);
      s.event.attendees.add(
        Attendee(
          id: 'a1',
          name: '손님',
          gender: 'M',
          age: 30,
          checkIn: start,
          checkOut: end,
          roomId: s.event.rooms.single.id,
        ),
      );
      expect(s.wouldLoseRoom('1').single.name, '손님');
      final n = s.removeRegistration('1');
      expect((n.people, n.rooms), (0, 1));
      expect(s.event.rooms, isEmpty);
      expect(s.event.attendees.single.roomId, isNull);
    });

    test('새 집회로 방을 복사하면 신청 연결은 풀린다', () {
      final s = tmpStore();
      s.syncHomestayRooms(g, [homeReg('1', '김호스트')]);
      final copied = copyEvent(
        s.event,
        name: '내년',
        start: DateTime(2027, 10, 8),
        end: DateTime(2027, 10, 10),
        rooms: true,
      );
      expect(copied.rooms.single.registrationId, isNull);
    });

    test('기간을 나누면 뒤쪽이 미배정으로 떨어지고, 정원도 제 기간만 찬다', () {
      final s = Store()
        ..event = Event(
          name: 'x',
          startDate: DateTime(2026, 10, 9),
          endDate: DateTime(2026, 10, 12), // 3박
          rooms: [
            Room(id: 'A', roomNo: '김호스트', capacity: 1),
            Room(id: 'B', roomNo: '박호스트', capacity: 1),
          ],
        );
      final kid = Attendee(
        id: 'k1',
        name: '아이',
        gender: 'M',
        age: 12,
        roomId: 'A',
        checkIn: DateTime(2026, 10, 9),
        checkOut: DateTime(2026, 10, 12),
      );
      s.event.attendees.add(kid);
      final a = s.event.rooms.first, b = s.event.rooms.last;
      expect(occupancyByNight(s.occupantsOf(a), s.event.nights), [1, 1, 1]);

      final later = s.splitStay(kid, DateTime(2026, 10, 11))!;
      expect(kid.checkOut, DateTime(2026, 10, 11)); // 앞쪽은 2박으로 줄고
      expect((later.checkIn, later.checkOut), (
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 12),
      ));
      expect(later.roomId, isNull); // 뒤쪽은 미배정
      expect(later.personId, kid.personId); // 같은 사람
      expect(s.unassigned.single.id, later.id);
      expect(s.partsOf(kid), hasLength(2));
      // 앞쪽 집은 이제 마지막 밤을 차지하지 않는다 — 그 밤은 다른 집에 줄 수 있다
      expect(occupancyByNight(s.occupantsOf(a), s.event.nights), [1, 1, 0]);

      s.assignAll([later], 'B');
      expect(occupancyByNight(s.occupantsOf(b), s.event.nights), [0, 0, 1]);
      expect(s.peakOccupancy(a), 1); // 정원 1인 집이 넘치지 않는다
      expect(s.peakOccupancy(b), 1);

      // 경계 밖 날짜로는 나눌 수 없다
      expect(s.splitStay(later, DateTime(2026, 10, 9)), isNull);
      expect(s.splitStay(later, DateTime(2026, 10, 12)), isNull);

      // 나눈 흔적은 저장을 거쳐도 남는다
      final back = Event.fromJson(s.event.toJson());
      expect(
        back.attendees.map((x) => x.personId).toSet(),
        {kid.id},
      );
    });

    test('가정이 신청한 기간이 방에 실린다', () {
      final s = tmpStore();
      // 10/9~10/11 집회에서 10/10 하루만 받겠다고 신청한 가정
      final r = homeReg('1', '김호스트')
        ..people.first.days = [DateTime(2026, 10, 10)];
      s.syncHomestayRooms(g, [r]);
      final room = s.event.rooms.single;
      expect(room.hostFrom, DateTime(2026, 10, 10));
      expect(room.hostTo, DateTime(2026, 10, 11));
      // 날짜를 안 고른 가정은 집회 전체
      s.syncHomestayRooms(g, [r, homeReg('2', '이호스트')]);
      final all = s.event.rooms.firstWhere((x) => x.roomNo == '이호스트');
      expect((all.hostFrom, all.hostTo), (start, end));
      // 저장을 거쳐도 남는다
      expect(
        Event.fromJson(s.event.toJson()).rooms.first.hostFrom,
        DateTime(2026, 10, 10),
      );
    });

    test('중간을 비워 두고 신청한 가정은 안 받는 밤이 방에 남는다', () {
      // 10/9~10/14 집회에서 10/9~10/10, 10/12~10/13 만 받겠다고 신청한 가정.
      // 10/10 밤과 10/11 밤은 안 받는다 — 기간(10/9~10/13)만 보면 감춰진다.
      final long = Gathering(
        id: 'h1',
        name: '홈스테이',
        kind: GatheringKind.homestay,
        start: DateTime(2026, 10, 9),
        end: DateTime(2026, 10, 14),
        formFields: [homestayCapacityField],
      );
      final s = Store()
        ..event = Event(
          name: 'x',
          startDate: DateTime(2026, 10, 9),
          endDate: DateTime(2026, 10, 14),
        );
      final r = homeReg('1', '김호스트')
        ..people.first.days = [
          DateTime(2026, 10, 9),
          DateTime(2026, 10, 10),
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 13),
        ];
      s.syncHomestayRooms(long, [r]);
      final room = s.event.rooms.single;
      expect((room.hostFrom, room.hostTo), (
        DateTime(2026, 10, 9),
        DateTime(2026, 10, 13),
      ));
      expect(room.hostNights, [DateTime(2026, 10, 9), DateTime(2026, 10, 12)]);
      expect(room.hostsOn(DateTime(2026, 10, 9)), isTrue);
      expect(room.hostsOn(DateTime(2026, 10, 10)), isFalse); // 비워 둔 밤
      expect(room.hostsOn(DateTime(2026, 10, 11)), isFalse);
      expect(room.hostsOn(DateTime(2026, 10, 12)), isTrue);
      // 저장을 거쳐도 남는다
      expect(
        Event.fromJson(s.event.toJson()).rooms.single.hostNights,
        room.hostNights,
      );

      // 자동배정은 안 받는 밤에 묵는 사람을 이 집에 넣지 않는다
      s.event.attendees.add(
        Attendee(
          id: 'k1',
          name: '아이하나',
          gender: 'M',
          age: 12,
          checkIn: DateTime(2026, 10, 9),
          checkOut: DateTime(2026, 10, 11), // 10/9·10/10 밤
        ),
      );
      expect(autoAssign(s.event, AutoRule()).unplaced.single.id, 'k1');

      // 빈틈 없이 신청한 가정은 기간만으로 충분하다 (목록을 남기지 않는다)
      final r2 = homeReg('2', '이호스트')
        ..people.first.days = [
          DateTime(2026, 10, 9),
          DateTime(2026, 10, 10),
          DateTime(2026, 10, 11),
        ];
      s.syncHomestayRooms(long, [r, r2]);
      final gapless = s.event.rooms.firstWhere((x) => x.roomNo == '이호스트');
      expect(gapless.hostNights, isNull);
      expect(gapless.hostsOn(DateTime(2026, 10, 10)), isTrue);
    });

    test('기간을 골라 배정하면 그만큼만 들어가고 나머지는 미배정으로 남는다', () {
      final s = Store()
        ..event = Event(
          name: 'x',
          startDate: DateTime(2026, 10, 9),
          endDate: DateTime(2026, 10, 13), // 4박
          rooms: [Room(id: 'A', roomNo: '김호스트', capacity: 4)],
          attendees: [
            Attendee(
              id: 'k1',
              name: '아이',
              gender: 'M',
              age: 12,
              checkIn: DateTime(2026, 10, 9),
              checkOut: DateTime(2026, 10, 13),
            ),
          ],
        );
      // 가운데 2박만 이 집에
      final placed = s.assignRange(
        [s.event.attendees.single],
        'A',
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 12),
      );
      expect(placed, hasLength(1));
      expect((placed.single.checkIn, placed.single.checkOut), (
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 12),
      ));
      expect(placed.single.roomId, 'A');
      // 앞 1박·뒤 1박은 미배정 조각으로 남는다
      expect(s.event.attendees, hasLength(3));
      expect(s.unassigned.map((a) => a.checkIn).toList()..sort(), [
        DateTime(2026, 10, 9),
        DateTime(2026, 10, 12),
      ]);
      expect(s.event.attendees.every((a) => a.personId == 'k1'), isTrue);
      expect(
        occupancyByNight(s.occupantsOf(s.event.rooms.single), s.event.nights),
        [0, 1, 1, 0],
      );

      // 일정과 안 겹치는 기간은 건너뛴다 (엉뚱한 배정을 만들지 않는다)
      final before = s.event.attendees.length;
      expect(
        s.assignRange(s.unassigned, 'A', DateTime(2026, 11, 1), DateTime(2026, 11, 2)),
        isEmpty,
      );
      expect(s.event.attendees, hasLength(before));
    });

    test('배정 결과는 조회 응답에서 읽는다', () {
      final r = Registration.fromRow({
        'id': 'r1',
        'gathering_id': 'h1',
        'phone': '01011112222',
        'people': [],
        'quoted': 0,
        'status': 'confirmed',
        'created_at': '2026-09-10T00:00:00Z',
        'assigned': [
          {'name': '손님1', 'gender': 'F', 'age': 20, 'phone': '01000001111'},
          {'name': '손님2'},
        ],
      });
      expect(r.assigned, hasLength(2));
      expect(r.assigned.first.name, '손님1');
      expect(r.assigned.first.phone, '01000001111');
      expect(r.assigned.last.age, 0);
      expect(r.assigned.last.phone, isNull);
      // 운영자가 읽는 registrations 행에는 assigned 가 없다.
      expect(reg('r2', RegStatus.pending, []).assigned, isEmpty);
    });
  });
}
