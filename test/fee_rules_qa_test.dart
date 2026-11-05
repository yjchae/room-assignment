// QA: 날짜별 당일 금액·연령 구분·회비 안내 문구 (PLAN_GATHERING §27) 회귀 테스트.
// 기존 집회 무영향(회비 JSON 바이트 비교·금액), 경계 조건, 집회 설정 화면 저장, 신청 웹 회비표.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/main_public.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/screens/gathering_settings.dart';

import 'gathering_widget_test.dart' show FakeRemote, pumpPage, setView;

final s = DateTime(2026, 10, 9); // 금
final sat = DateTime(2026, 10, 10);
final e = DateTime(2026, 10, 11); // 일

Person who(int by, List<DateTime>? days, {List<DateTime>? stays}) =>
    Person(name: 'x', gender: 'M', birthYear: by, days: days, stays: stays);

Quote qt(FeeRule f, List<Person> ps, {DateTime? to, bool dateless = false}) =>
    quote(
      f,
      start: s,
      end: to ?? e,
      people: ps,
      appliedAt: DateTime(2026, 9, 20),
      dateless: dateless,
    );

/// §27 전 코드(HEAD~2)의 FeeRule.toJson 이 낸 문자열을 그대로 옮겼다. 새 코드에서 fromJson→toJson 이 같아야 한다.
const oldJson = {
  'sample': '{"full":{"adult":150000,"youth":120000,"child":100000,"kinder":60000,"infant":0},"perNight":{"adult":70000,"youth":60000},"dayOnly":{"adult":30000},"minAge":{"adult":19,"youth":13,"child":7,"kinder":4,"infant":0},"perRegistration":10000,"fullDiscountPct":0,"early":[],"freeDays":[]}',
  'free+early': '{"full":{"adult":150000},"perNight":{"adult":70000,"youth":60000},"dayOnly":{"adult":30000,"youth":20000,"child":10000},"minAge":{"adult":19,"youth":13,"child":7,"kinder":4,"infant":0},"perRegistration":10000,"fullDiscountPct":10,"early":[{"fromDays":30,"toDays":10,"pct":10},{"fromDays":60,"toDays":31,"pct":20}],"freeDays":["2026-10-11","2026-10-09"]}',
  'separate': '{"full":{"adult":50000},"perNight":{"adult":70000},"dayOnly":{"adult":20000,"youth":10000},"minAge":{"adult":19,"youth":13,"child":7,"kinder":4,"infant":0},"perRegistration":0,"fullDiscountPct":5,"early":[],"freeDays":["2026-10-10"],"lodgingSeparate":true,"lodging":{"adult":40000,"youth":30000,"infant":0}}',
  'minAge-changed': '{"full":{"adult":100000,"youth":80000,"child":50000,"kinder":30000},"perNight":{"adult":50000},"dayOnly":{"adult":20000},"minAge":{"adult":20,"youth":14,"child":8,"kinder":5,"infant":0},"perRegistration":5000,"fullDiscountPct":0,"early":[],"freeDays":[]}',
  'dateless': '{"full":{"adult":30000,"youth":20000},"perNight":{},"dayOnly":{},"minAge":{"adult":19,"youth":13,"child":7,"kinder":4,"infant":0},"perRegistration":5000,"fullDiscountPct":0,"early":[],"freeDays":[]}',
};

/// 옛 코드에서 찍은 금액: 아래 [mixed] 가족을 2박 집회 / 날짜 없는 집회로 계산한 total.
const oldTotals = {
  'sample': (590000, 930000),
  'free+early': (440200, 528400),
  'separate': (443500, 199500),
  'minAge-changed': (355000, 545000),
  'dateless': (85000, 145000),
};

List<Person> mixed() {
  List<DateTime> d(List<int> o) => [
    for (final i in o) s.add(Duration(days: i)),
  ];
  Person p(int by, List<int>? o, {List<int>? stays}) => Person(
    name: 'x',
    gender: 'M',
    birthYear: by,
    days: o == null ? null : d(o),
    stays: stays == null ? null : d(stays),
  );
  return [
    p(1985, null), p(2012, [0, 1, 2]), p(2018, [0]), p(2022, [1]), //
    p(2024, [2]), p(0, [0, 1]), p(2030, [1, 2]), p(2007, [0, 2]),
    p(2013, []), p(2006, [0, 1, 2], stays: [0]), p(1990, [1], stays: [1]),
    p(2019, [0, 1], stays: []),
  ];
}

void main() {
  group('1. 기존 집회 무영향', () {
    for (final MapEntry(key: name, value: js) in oldJson.entries) {
      test('$name: fromJson→toJson 바이트 같음, 금액 같음', () {
        final f = FeeRule.fromJson(jsonDecode(js));
        expect(jsonEncode(f.toJson()), js);
        expect(f.toJson().containsKey('groups'), isFalse);
        expect(f.toJson().containsKey('dayPrices'), isFalse);
        expect(qt(f, mixed()).total, oldTotals[name]!.$1);
        expect(
          quote(
            f,
            start: s,
            end: s,
            people: mixed(),
            appliedAt: DateTime(2026, 9, 20),
            dateless: true,
          ).total,
          oldTotals[name]!.$2,
        );
        // Gathering 행 왕복(copy)도 같다
        final g = Gathering.fromRow({
          'id': 'g',
          'name': 'n',
          'start_date': '2026-10-09',
          'end_date': '2026-10-11',
          'fee': jsonDecode(js),
        });
        expect(jsonEncode(g.copy().fee.toJson()), js);
      });
    }

    test('fee_note 칸 없는 행 → toRow 에 fee_note 없음, copy 를 거쳐도 없음', () {
      final g = Gathering.fromRow({
        'id': 'g',
        'name': 'n',
        'start_date': '2026-10-09',
        'end_date': '2026-10-11',
        'fee': jsonDecode(oldJson['sample']!),
      });
      expect(g.toRow().containsKey('fee_note'), isFalse);
      expect(g.copy().toRow().containsKey('fee_note'), isFalse);
      expect(g.copy().copy().toRow().containsKey('fee_note'), isFalse);
      // 칸이 있는 DB(값 null)는 null 을 보낸다 — 트리거는 null→null 이라 통과
      final h = Gathering.fromRow({...g.toRow(), 'id': 'g', 'fee_note': null});
      expect(h.toRow().containsKey('fee_note'), isTrue);
      expect(h.toRow()['fee_note'], isNull);
      expect(h.copy().toRow().containsKey('fee_note'), isTrue);
    });
  });

  group('2. 날짜별 당일 금액 경계', () {
    FeeRule rule() => FeeRule(
      full: {AgeGroup.adult: 100000, AgeGroup.youth: 80000},
      perNight: {AgeGroup.adult: 40000, AgeGroup.youth: 30000},
      dayOnly: {AgeGroup.adult: 20000, AgeGroup.youth: 15000},
      perRegistration: 5000,
    );

    test('무료 + 지정이 겹치면 무료가 이긴다 (freeDay 판정 = 무료 날)', () {
      final f = rule()
        ..freeDays = [s]
        ..dayPrices = {
          s: {AgeGroup.adult: 7000},
        };
      expect(f.dayPriceOn(AgeGroup.adult, s), 0);
      final r = qt(f, [
        who(1980, [s]),
      ]);
      expect(r.lines.single.amount, 0);
      expect(r.freeDayOnly, isTrue);
      expect(r.total, 0);
    });

    test('지정 0원: 무료 날이 아니라 가족당 금액이 붙는다', () {
      final f = rule()
        ..dayPrices = {
          s: {AgeGroup.adult: 0},
        };
      final r = qt(f, [
        who(1980, [s]),
      ]);
      expect(r.lines.single.amount, 0);
      expect(r.lines.single.freeDay, isFalse);
      expect(r.noPayment, isFalse);
      expect(r.total, 5000);
    });

    test('일부 구분만 지정: 나머지 구분은 기본 당일 금액, 시간 붙은 키도 그 날로 본다', () {
      final f = rule()
        ..dayPrices = {
          DateTime(2026, 10, 9, 13, 30): {AgeGroup.adult: 9000},
        };
      expect(f.dayPriceOn(AgeGroup.adult, s), 9000);
      expect(f.dayPriceOn(AgeGroup.youth, s), 15000);
      expect(f.dayPriceOn(AgeGroup.child, s), 0);
      expect(
        jsonEncode(f.toJson()['dayPrices']),
        '{"2026-10-09":{"adult":9000}}',
      );
    });

    test('부분 참석 상한: 금·일 당일(앞뒤 안 이어짐) 합이 전체 참석 금액을 넘지 않는다', () {
      final f = rule()
        ..dayPrices = {
          s: {AgeGroup.adult: 70000},
          e: {AgeGroup.adult: 70000},
        };
      expect(
        qt(f, [
          who(1980, [s, e]),
        ]).lines.single.amount,
        100000,
      );
    });

    test('1박 이상 묵는 날엔 당일 금액을 안 쓴다 (금·토 이어짐 = 1박)', () {
      final f = rule()
        ..dayPrices = {
          s: {AgeGroup.adult: 1},
          sat: {AgeGroup.adult: 1},
        };
      expect(
        qt(f, [
          who(1980, [s, sat]),
        ]).lines.single.amount,
        40000,
      );
      // 토·일 이어짐 + 금은 떨어져 있지 않음(금·토·일 = 전체) → 정액
      expect(
        qt(f, [
          who(1980, [s, sat, e]),
        ]).lines.single.amount,
        100000,
      );
    });

    test('숙박비 별도: 참가일마다 그 날 금액(묵어도), 숙박비는 그대로, 상한 = 전체 참가비', () {
      final f = rule()
        ..lodgingSeparate = true
        ..full = {}
        ..lodging = {AgeGroup.adult: 30000}
        ..dayPrices = {
          s: {AgeGroup.adult: 5000},
        };
      // 금·토 참가, 금 밤 숙박: 참가비 5,000 + 20,000, 숙박 30,000
      final l = qt(f, [
        who(1980, [s, sat], stays: [s]),
      ]).lines.single;
      expect(l.participation, 25000);
      expect(l.lodging, 30000);
      // 전체 참가(정액 비움 = 하루 × 3일 = 60,000, 날짜별 금액은 안 봄)
      expect(f.fullPrice(AgeGroup.adult, 2), 60000);
      expect(
        qt(f, [
          who(1980, [s, sat, e], stays: []),
        ]).lines.single.participation,
        60000,
      );
    });

    test('기간 밖·날짜 없는 집회의 지정 금액은 계산에 안 들어간다', () {
      final f = rule()
        ..dayPrices = {
          DateTime(2026, 12, 25): {AgeGroup.adult: 1},
          s: {AgeGroup.adult: 1},
        };
      expect(
        qt(f, [
          who(1980, [e]),
        ]).lines.single.amount,
        20000,
      );
      // 날짜 없는 집회 = 참가 = 전체 참석 금액
      expect(
        qt(f, [who(1980, null)], to: s, dateless: true).lines.single.amount,
        100000,
      );
    });

    test('quote 는 일정 없는 날을 모른다 — 그 날 지정 금액은 저장 화면이 지운다 (화면 테스트 2)', () {
      // quote 는 offDays 를 모른다 — 일정 없는 날을 고른 옛 신청이 있으면 그 날 금액으로 센다.
      final f = rule()
        ..dayPrices = {
          sat: {AgeGroup.adult: 1},
        };
      expect(
        qt(f, [
          who(1980, [sat]),
        ]).lines.single.amount,
        1,
      );
    });
  });

  group('3. 연령 구분', () {
    test('영유아를 빼면 0~3세는 유치(가장 낮은 시작 나이)로, JSON 에 infant 키가 안 남는다', () {
      final f = FeeRule.fromJson(jsonDecode(oldJson['sample']!));
      expect(f.removeGroup(AgeGroup.infant), isTrue);
      expect(f.groupOf(3), AgeGroup.kinder);
      expect(f.groupOf(0), AgeGroup.kinder);
      expect(f.groupOf(-5), AgeGroup.kinder);
      expect(f.groupOf(4), AgeGroup.kinder);
      final js = jsonEncode(f.toJson());
      expect(js.contains('infant'), isFalse);
      expect(f.toJson()['groups'], hasLength(4));
      final back = FeeRule.fromJson(jsonDecode(js));
      expect(back.groupOf(2), AgeGroup.kinder);
      expect(jsonEncode(back.toJson()), js);
    });

    test('경계 나이: 장년(60) 추가 후 59 = 성인, 60 = 장년, 이름 바꿔도 같은 구분', () {
      final f = FeeRule();
      final senior = f.addGroup('장년', 60);
      expect(senior.name, matches(RegExp(r'^c[0-9a-z]{6}$')));
      expect(f.groupOf(59), AgeGroup.adult);
      expect(f.groupOf(60), senior);
      expect(f.groupOf(19), AgeGroup.adult);
      expect(f.groupOf(18), AgeGroup.youth);
      f.groups[5] = senior.withLabel('어르신');
      expect(f.groupOf(70), senior);
      expect(f.labelOf(senior), '어르신');
      expect(f.groupOf(70).label, '어르신');
    });

    test('구분 하나만: 누구든 그 구분, 마지막 하나는 못 뺀다', () {
      final f = FeeRule(groups: [AgeGroup.adult], full: {AgeGroup.adult: 1000});
      expect(f.groupOf(3), AgeGroup.adult);
      expect(f.groupOf(-1), AgeGroup.adult);
      expect(f.removeGroup(AgeGroup.adult), isFalse);
      final back = FeeRule.fromJson(f.toJson());
      expect(back.groups, [AgeGroup.adult]);
      expect(back.groupOf(1), AgeGroup.adult);
      expect(qt(back, [who(2025, null)]).summary, '성인 1');
    });

    test('출생연도 0(모름) = 성인 — 장년(60~)을 더해도 성인 금액 그대로', () {
      final f = FeeRule(full: {AgeGroup.adult: 100000});
      expect(qt(f, [who(0, null)]).lines.single.group, AgeGroup.adult);
      final senior = f.addGroup('장년', 60);
      f.full[senior] = 50000;
      final l = qt(f, [who(0, null)]).lines.single;
      expect(l.group, AgeGroup.adult);
      expect(l.amount, 100000);
      // 출생연도를 적은 60세는 장년.
      expect(qt(f, [who(1966, null)]).lines.single.group, senior);
    });

    test('성인을 지우면 모름은 19세가 걸리는 구분', () {
      final f = FeeRule()..removeGroup(AgeGroup.adult);
      expect(f.unknownGroup, AgeGroup.youth);
      expect(qt(f, [who(0, null)]).lines.single.group, AgeGroup.youth);
    });

    test('새 구분 금액을 비우면 그 구분은 0원 (기존 규칙: 키 없음 = 0원)', () {
      final f = FeeRule(full: {AgeGroup.adult: 100000});
      f.addGroup('장년', 60);
      expect(qt(f, [who(1950, null)]).lines.single.amount, 0);
      expect(qt(f, [who(1950, null)]).total, 0);
    });

    test('기본 구분 그대로면 groups 키 없음, 이름을 바꾸면 생기고 되돌리면 다시 없음', () {
      final f = FeeRule();
      expect(f.toJson().containsKey('groups'), isFalse);
      f.groups[0] = AgeGroup.adult.withLabel('어른');
      expect(f.toJson()['groups'], hasLength(5));
      f.groups[0] = AgeGroup.adult;
      expect(f.toJson().containsKey('groups'), isFalse);
    });

    test('지운 구분 키는 금액·나이·날짜별 금액 맵 어디에도 안 남는다', () {
      final f = FeeRule(
        full: {AgeGroup.kinder: 1},
        perNight: {AgeGroup.kinder: 2},
        dayOnly: {AgeGroup.kinder: 3},
        lodging: {AgeGroup.kinder: 4},
        dayPrices: {
          s: {AgeGroup.kinder: 5},
          sat: {AgeGroup.kinder: 6, AgeGroup.adult: 7},
        },
      );
      f.removeGroup(AgeGroup.kinder);
      final js = jsonEncode(f.toJson());
      expect(js.contains('kinder'), isFalse);
      expect(f.dayPrices.keys, [sat]);
      expect(f.toJson()['dayPrices'], {
        '2026-10-10': {'adult': 7},
      });
    });

    test('summary·QuoteLine 라벨은 구분 순서·고친 이름으로', () {
      final f = FeeRule();
      final senior = f.addGroup('장년', 60);
      f.groups
        ..remove(senior)
        ..insert(0, senior);
      f.groups[1] = AgeGroup.adult.withLabel('어른');
      final r = qt(f, [who(2015, null), who(1950, null), who(1990, null)]);
      expect(r.summary, '장년 1 · 어른 1 · 초등 1');
      expect(r.lines[2].group.label, '어른');
    });
  });

  group('5. 설정을 바꾸면 기존 신청의 계산 금액이 바뀐다 (quoted 는 그대로)', () {
    test('날짜별 금액·구분 변경 → beforeDiscount 가 quoted 와 달라진다', () {
      final g = Gathering(
        id: 'g',
        name: 'n',
        start: s,
        end: e,
        fee: FeeRule(
          full: {AgeGroup.adult: 100000},
          dayOnly: {AgeGroup.adult: 20000},
          perRegistration: 5000,
        ),
      );
      final ppl = [
        who(1980, [s]),
      ];
      final quoted = g.quoteFor(ppl, DateTime(2026, 9, 1)).beforeDiscount;
      expect(quoted, 25000);
      g.fee.dayPrices = {
        s: {AgeGroup.adult: 10000},
      };
      expect(g.quoteFor(ppl, DateTime(2026, 9, 1)).beforeDiscount, 15000);
      // 구분 추가로 같은 사람이 다른 구분이 된다
      g.fee.dayPrices = {};
      final mid = g.fee.addGroup('청년', 20);
      g.fee.dayOnly[mid] = 12000;
      // 전체 참석 금액을 안 적으면 상한(0원)에 걸려 당일도 0원 — 기존 규칙 그대로
      expect(
        g.quoteFor([
          who(2000, [s]),
        ], DateTime(2026, 9, 1)).beforeDiscount,
        5000,
      );
      g.fee.full[mid] = 80000;
      final ppl2 = [
        who(2000, [s]),
      ];
      expect(g.quoteFor(ppl2, DateTime(2026, 9, 1)).lines.single.group, mid);
      expect(g.quoteFor(ppl2, DateTime(2026, 9, 1)).beforeDiscount, 17000);
    });
  });

  group('화면', () {
    setUp(() {
      canConfigure.value = true;
      passwordRecovery.value = false;
    });

    Future<FakeRemote> openSettings(
      WidgetTester tester,
      Map<String, dynamic> row,
    ) async {
      final fake = FakeRemote();
      remote = fake;
      final g = Gathering.fromRow(row);
      fake.gs.add(g.copy());
      current.value = g.copy();
      store.event = Event(name: 'n', startDate: g.start, endDate: g.end);
      setView(tester, const Size(1400, 4400));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      return fake;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    for (final MapEntry(key: name, value: js) in oldJson.entries) {
      for (final variant in ['보통', '일정 없는 날', '날짜 없는 집회']) {
        testWidgets('1. 집회 설정 열고 그대로 저장: $name · $variant — 회비 JSON 바이트 같음', (
          tester,
        ) async {
          final dl = variant == '날짜 없는 집회';
          final fake = await openSettings(tester, {
            'id': 'g1',
            'name': 'n',
            'start_date': '2026-10-09',
            'end_date': dl ? '2026-10-09' : '2026-10-11',
            if (dl) 'dateless': true,
            if (variant == '일정 없는 날') 'off_days': ['2026-10-12'],
            'fee': jsonDecode(js),
          });
          await save(tester);
          final out = fake.gs.single;
          // 저장 화면은 기간 안 1박당·당일 등을 다시 쓰므로, 옛 코드(_collect)가 낸 결과와 비교한다:
          // 화면에 없는 값(날짜 없는 집회의 1박당·당일)을 비우는 것 말고는 그대로다.
          final want = FeeRule.fromJson(jsonDecode(js));
          if (dl) {
            want
              ..perNight = {}
              ..dayOnly = {}
              ..lodging = {}
              ..fullDiscountPct = 0
              ..freeDays = []
              ..lodgingSeparate = false;
          }
          expect(jsonEncode(out.fee.toJson()), jsonEncode(want.toJson()));
          expect(out.toRow().containsKey('fee_note'), isFalse);
        });
      }
    }

    testWidgets('2. 무료 날·지정 금액이 일정 없는 날이면 저장 때 지우고, 기간 밖 날짜는 남긴다', (
      tester,
    ) async {
      final fake = await openSettings(tester, {
        'id': 'g1',
        'name': 'n',
        'start_date': '2026-10-09',
        'end_date': '2026-10-11',
        'off_days': ['2026-10-10'],
        'fee': {
          'dayOnly': {'adult': 20000},
          'freeDays': ['2026-10-10', '2026-12-25'],
          'dayPrices': {
            '2026-10-10': {'adult': 1},
            '2026-12-24': {'adult': 2},
            '2026-10-11': {'adult': 3},
          },
        },
      });
      await save(tester);
      final f = fake.gs.single.fee;
      expect(f.freeDays, [DateTime(2026, 12, 25)]);
      expect(f.dayPrices, {
        DateTime(2026, 12, 24): {AgeGroup.adult: 2},
        DateTime(2026, 10, 11): {AgeGroup.adult: 3},
      });
    });

    testWidgets('3. 영유아를 빼고 저장 → 회비 JSON 에 infant 가 없고 groups 넷', (
      tester,
    ) async {
      final fake = await openSettings(tester, {
        'id': 'g1',
        'name': 'n',
        'start_date': '2026-10-09',
        'end_date': '2026-10-11',
        'fee': {
          ...jsonDecode(oldJson['sample']!) as Map,
          'dayPrices': {
            '2026-10-09': {'infant': 1000},
          },
        },
      });
      await tester.tap(find.byTooltip('구분 삭제').at(4));
      await tester.pumpAndSettle();
      await save(tester);
      final js = jsonEncode(fake.gs.single.fee.toJson());
      expect(js.contains('infant'), isFalse);
      expect(fake.gs.single.fee.toJson()['groups'], hasLength(4));
      expect(fake.gs.single.fee.dayPrices, isEmpty);
      expect(fake.gs.single.fee.groupOf(1), AgeGroup.kinder);
    });

    testWidgets('4. 운영스탭/보조운영자(주인 아님)가 저장해도 fee_note 는 서버 값 그대로', (
      tester,
    ) async {
      final fake = FakeRemote()
        ..full = false
        ..managed.add('g1');
      remote = fake;
      final g = Gathering.fromRow({
        'id': 'g1',
        'name': 'n',
        'start_date': '2026-10-09',
        'end_date': '2026-10-11',
        'fee_note': '주인 문구',
      });
      fake.gs.add(g.copy());
      current.value = g.copy();
      store.event = Event(name: 'n', startDate: g.start, endDate: g.end);
      setView(tester, const Size(1400, 4400));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      final note = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '회비 안내 문구',
      );
      expect(tester.widget<TextField>(note).readOnly, isTrue);
      // readOnly 라도 enterText 는 컨트롤러를 바꾼다 — 그래도 저장은 안 바뀌어야 한다
      tester.widget<TextField>(note).controller!.text = '바꿔 봄';
      await save(tester);
      expect(fake.gs.single.feeNote, '주인 문구');
      expect(fake.gs.single.toRow()['fee_note'], '주인 문구');
    });

    Gathering pub({String? note, bool requireBirth = false}) => Gathering(
      id: 'g1',
      name: '수양회',
      start: s,
      end: e,
      open: true,
      requiredFields: requireBirth ? ['birthYear', 'gender'] : ['gender'],
      bank: Bank(bank: '국민', account: '0', holder: 'x'),
      fee: FeeRule(full: {AgeGroup.adult: 100000}),
      feeNote: note,
    );

    Future<void> openPublic(WidgetTester tester, Gathering g) async {
      final fake = FakeRemote()..gs.add(g);
      remote = fake;
      setView(tester, const Size(400, 1600));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('4. 신청 웹: 안내 문구가 없으면 자동 나이 설명 두 줄이 그대로 보인다 (기존 집회)', (
      tester,
    ) async {
      await openPublic(tester, pub());
      expect(find.text('· 나이는 2026년 − 출생연도로 계산합니다.'), findsOneWidget);
      expect(find.text('· 출생연도를 비워 두면 성인 금액으로 계산합니다.'), findsOneWidget);
    });

    testWidgets('4. 신청 웹: 출생연도 필수면 자동 문구는 첫 줄만', (tester) async {
      await openPublic(tester, pub(requireBirth: true));
      expect(find.text('· 나이는 2026년 − 출생연도로 계산합니다.'), findsOneWidget);
      expect(find.textContaining('비워 두면'), findsNothing);
    });

    testWidgets('4. 신청 웹: 안내 문구의 빈 줄은 버리고 자동 문구를 끼워 넣지 않는다', (tester) async {
      await openPublic(tester, pub(note: '첫 줄\n\n둘째 줄'));
      expect(find.text('· 첫 줄'), findsOneWidget);
      expect(find.text('· 둘째 줄'), findsOneWidget);
      expect(find.textContaining('출생연도'), findsNothing);
    });

    testWidgets('4. 신청 웹: 공백뿐인 문구는 자동 문구', (tester) async {
      await openPublic(tester, pub(note: '  \n '));
      expect(find.text('· 나이는 2026년 − 출생연도로 계산합니다.'), findsOneWidget);
    });
  });
}
