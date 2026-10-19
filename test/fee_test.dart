import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';

// 기획서 §3.3 예시 집회: 2026-10-09(금) ~ 10-11(일), 2박3일
final start = DateTime(2026, 10, 9);
final end = DateTime(2026, 10, 11);
// 38일 전 = 09-01, 19일 전 = 09-20
const earlyBird = (fromDays: 38, toDays: 19, pct: 10);

/// 기획서 §3.2 금액표.
FeeRule planRule({
  int perRegistration = 10000,
  int fullDiscountPct = 0,
  List<EarlyDiscount>? early,
}) => FeeRule(
  full: {
    AgeGroup.adult: 150000,
    AgeGroup.youth: 120000,
    AgeGroup.child: 100000,
    AgeGroup.kinder: 60000,
    AgeGroup.infant: 0,
  },
  perNight: {
    AgeGroup.adult: 70000,
    AgeGroup.youth: 60000,
    AgeGroup.child: 50000,
    AgeGroup.kinder: 30000,
  },
  dayOnly: {
    AgeGroup.adult: 30000,
    AgeGroup.youth: 25000,
    AgeGroup.child: 20000,
    AgeGroup.kinder: 10000,
  },
  perRegistration: perRegistration,
  fullDiscountPct: fullDiscountPct,
  early: early ?? [earlyBird],
);

Person p(String name, int birthYear, {DateTime? checkIn, DateTime? checkOut}) =>
    Person(
      name: name,
      gender: 'M',
      birthYear: birthYear,
      checkIn: checkIn,
      checkOut: checkOut,
    );

Quote q(
  FeeRule f,
  List<Person> people, {
  DateTime? on,
  DateTime? from,
  DateTime? to,
}) => quote(
  f,
  start: from ?? start,
  end: to ?? end,
  people: people,
  appliedAt: on ?? DateTime(2026, 9, 10),
);

void main() {
  test('기획서 예시: 가족 4명, 얼리버드 10%, 그룹당 1만원 = 415,000원', () {
    final r = q(planRule(), [
      p('아빠', 1985),
      p('엄마', 1987),
      p('첫째', 2012),
      p('둘째', 2021, checkIn: DateTime(2026, 10, 10)), // 토~일 1박
    ]);
    expect(r.lines.map((l) => l.group), [
      AgeGroup.adult,
      AgeGroup.adult,
      AgeGroup.youth,
      AgeGroup.kinder,
    ]);
    expect(r.lines.map((l) => l.amount), [150000, 150000, 120000, 30000]);
    expect(r.lines.last.nights, 1);
    expect(r.lines.last.full, isFalse);
    expect(r.subtotal, 450000);
    expect(r.earlyDiscount, 45000);
    expect(r.total, 415000);
  });

  test('연령 구분 경계 (연 나이)', () {
    final f = FeeRule();
    expect(
      {
        for (final a in [19, 18, 13, 12, 7, 6, 4, 3, 0, -1]) a: f.groupOf(a),
      },
      {
        19: AgeGroup.adult,
        18: AgeGroup.youth,
        13: AgeGroup.youth,
        12: AgeGroup.child,
        7: AgeGroup.child,
        6: AgeGroup.kinder,
        4: AgeGroup.kinder,
        3: AgeGroup.infant,
        0: AgeGroup.infant,
        -1: AgeGroup.infant, // 출생연도 오타로 미래 연도
      },
    );
    // 나이는 집회 연도 − 출생연도: 2026년 집회에서 2007년생 = 19 = 성인
    expect(q(planRule(), [p('a', 2007)]).lines.single.group, AgeGroup.adult);
    expect(q(planRule(), [p('b', 2008)]).lines.single.group, AgeGroup.youth);
  });

  test('구분 시작 나이를 바꾸면 따라간다', () {
    final f = FeeRule(minAge: {...FeeRule.defaultMinAge, AgeGroup.adult: 20});
    expect(f.groupOf(19), AgeGroup.youth);
    expect(f.groupOf(20), AgeGroup.adult);
  });

  test('영유아는 0원', () {
    final r = q(planRule(perRegistration: 0, early: []), [p('아기', 2025)]);
    expect(r.lines.single.group, AgeGroup.infant);
    expect(r.total, 0);
  });

  test('일정이 집회 기간 전체면 전체 참석 — 기간 밖 날짜는 잘라서 본다', () {
    final r = q(planRule(early: []), [
      p('딱 맞춤', 1990, checkIn: start, checkOut: end),
      p(
        '넘침',
        1990,
        checkIn: DateTime(2026, 10, 1),
        checkOut: DateTime(2026, 10, 30),
      ),
    ]);
    expect(r.lines.map((l) => l.full), [true, true]);
    expect(r.lines.map((l) => l.amount), [150000, 150000]);
  });

  test('당일(0박)은 당일 금액', () {
    final day = DateTime(2026, 10, 10);
    final r = q(planRule(early: []), [
      p('당일', 1990, checkIn: day, checkOut: day),
    ]);
    expect(r.lines.single.nights, 0);
    expect(r.lines.single.amount, 30000);
  });

  test('날짜 체크: 이어진 날 사이는 1박, 혼자 떨어진 날은 당일', () {
    // 10-09 ~ 10-12 (3박). 금·토 + 월 = 1박 70,000 + 당일 30,000
    final r = q(
      planRule(early: []),
      [
        Person(
          name: '띄엄',
          gender: 'M',
          birthYear: 1990,
          days: [
            DateTime(2026, 10, 12),
            DateTime(2026, 10, 9),
            DateTime(2026, 10, 10),
          ],
        ),
      ],
      from: DateTime(2026, 10, 9),
      to: DateTime(2026, 10, 12),
    );
    expect(r.lines.single.nights, 1);
    expect(r.lines.single.stay, '1박 + 당일');
    expect(r.lines.single.amount, 100000);
  });

  test('모든 날을 체크하면 전체 참석', () {
    final r = q(planRule(early: []), [
      Person(
        name: 'a',
        gender: 'M',
        birthYear: 1990,
        days: [start, DateTime(2026, 10, 10), end],
      ),
    ]);
    expect(r.lines.single.full, isTrue);
    expect(r.lines.single.amount, 150000);
  });

  test('모든 금액이 0이면 무료', () {
    expect(FeeRule().isFree, isTrue);
    expect(FeeRule(full: {AgeGroup.adult: 0}).isFree, isTrue);
    expect(FeeRule(perRegistration: 1000).isFree, isFalse);
    expect(planRule().isFree, isFalse);
    expect(
      [for (final s in RegStatus.values) s.labelFor(free: true)],
      ['대기', '확정', '취소'],
    );
    expect(RegStatus.pending.labelFor(free: false), '입금대기');
  });

  test('부분 참석 금액은 전체 참석 금액을 넘지 않는다', () {
    // 3박 집회, 1박 80,000 × 2박 = 160,000 > 전체 150,000 → 150,000
    final f = planRule(early: [])..perNight[AgeGroup.adult] = 80000;
    final r = q(
      f,
      [p('2박', 1990, checkIn: DateTime(2026, 10, 10))],
      from: DateTime(2026, 10, 9),
      to: DateTime(2026, 10, 12),
    );
    expect(r.lines.single.nights, 2);
    expect(r.lines.single.full, isFalse);
    expect(r.lines.single.amount, 150000);
  });

  test('전체 정액을 비우면 1박당 × 박수, 전체참석 할인 → 사전등록 할인 순서로 겹쳐 적용', () {
    final f = planRule(fullDiscountPct: 10)..full.remove(AgeGroup.adult);
    final r = q(f, [
      p('전체', 1990), // 70,000 × 2박 = 140,000 → 10% 할인 126,000
      p('1박', 1990, checkIn: DateTime(2026, 10, 10)), // 70,000 (전체참석 할인 없음)
    ]);
    expect(r.lines.map((l) => l.amount), [126000, 70000]);
    expect(r.subtotal, 196000);
    expect(r.total, 196000 * 90 ~/ 100 + 10000); // 186,400
  });

  test('사전등록 할인: 집회 며칠 전인지로, 양 끝 포함, 겹치면 큰 쪽', () {
    final f = planRule(
      perRegistration: 0,
      early: [
        earlyBird,
        (fromDays: 24, toDays: 23, pct: 20), // 09-15 ~ 09-16
      ],
    );
    final people = [p('a', 1990)];
    expect(q(f, people, on: DateTime(2026, 9, 1)).earlyPct, 10);
    expect(q(f, people, on: DateTime(2026, 9, 20, 23, 59)).earlyPct, 10);
    expect(q(f, people, on: DateTime(2026, 9, 21)).earlyPct, 0);
    expect(q(f, people, on: DateTime(2026, 9, 15)).earlyPct, 20);
    expect(q(f, people, on: DateTime(2026, 8, 31)).total, 150000);
    // 집회 날짜가 바뀌면 구간도 같이 움직인다: 10-19 시작이면 09-20 은 29일 전
    expect(
      q(
        f,
        people,
        on: DateTime(2026, 9, 20),
        from: DateTime(2026, 10, 19),
        to: DateTime(2026, 10, 21),
      ).earlyPct,
      10,
    );
    expect(daysBefore(start, 38), DateTime(2026, 9, 1));
  });

  test('원 미만 버림', () {
    final f = FeeRule(full: {AgeGroup.adult: 33333}, early: [earlyBird]);
    final r = q(f, [p('a', 1990)]);
    expect(r.total, 29999); // 33,333 × 0.9 = 29,999.7
    expect(r.subtotal - r.earlyDiscount, r.total);
  });

  test('참석자가 없으면 그룹당 금액도 붙지 않는다', () {
    final r = q(planRule(), []);
    expect(r.total, 0);
  });

  test('지정 할인: 합계(그룹당 포함)에서 % 또는 원을 빼고, 0 아래로 내려가지 않는다', () {
    final family = [p('아빠', 1985), p('엄마', 1987)];
    Quote d(Discount x) => quote(
      planRule(),
      start: start,
      end: end,
      people: family,
      appliedAt: DateTime(2026, 9, 10),
      discount: x,
    );
    final base = d(Discount.none).total;
    expect(d(Discount.none).specialDiscount, 0);
    expect(d(const Discount(pct: 50)).total, base - base ~/ 2);
    expect(d(const Discount(amount: 30000)).total, base - 30000);
    expect(d(const Discount(amount: 99999999)).total, 0);
    expect(d(const Discount(pct: 100)).total, 0);
    expect(d(const Discount(pct: 50)).beforeDiscount, base);
    // 참석자가 없으면 할인도 없다
    expect(q(planRule(), []).discount.isEmpty, isTrue);
  });

  test('할인율이 범위를 벗어나도 음수 금액이 나오지 않는다', () {
    final f = planRule(
      fullDiscountPct: 150,
      early: [(fromDays: 38, toDays: 9, pct: 200)],
    );
    final r = q(f, [p('a', 1990)]);
    expect(r.lines.single.amount, 0);
    expect(r.total, 10000); // 그룹당 금액만
  });

  group('당일 무료 날', () {
    // 금~화 수양회, 일요일(10-11)이 당일 무료 날. 당일 1만 · 1박 3만.
    final fri = DateTime(2026, 10, 9), sat = DateTime(2026, 10, 10);
    final sun = DateTime(2026, 10, 11), mon = DateTime(2026, 10, 12);
    final tue = DateTime(2026, 10, 13);
    FeeRule rule({List<DateTime>? free}) => FeeRule(
      perNight: {AgeGroup.adult: 30000},
      dayOnly: {AgeGroup.adult: 10000},
      perRegistration: 5000,
      freeDays: free ?? [sun],
    );
    Person on(List<DateTime> days) =>
        Person(name: '가', gender: 'M', birthYear: 1980, days: days);
    Quote fq(List<Person> people, {FeeRule? f}) =>
        q(f ?? rule(), people, from: fri, to: tue);
    int amount(List<DateTime> days) => fq([on(days)]).lines.single.amount;

    test('무료 날 당일만이면 0원, 가족당 금액도 없음', () {
      final r = fq([
        on([sun]),
        on([sun]),
      ]);
      expect(r.lines.map((l) => l.amount), [0, 0]);
      expect(r.total, 0);
      expect(r.lines.first.stay, '당일(무료)');
    });

    test('무료 날을 끼고 1박 이상이면 보통 금액', () {
      expect(amount([sat, sun]), 30000);
      expect(amount([sun, mon]), 30000);
      expect(amount([fri, sat, sun, mon, tue]), 120000);
    });

    test('무료 날 당일 + 다른 날 당일 = 다른 날 금액만, 가족당 금액 붙음', () {
      expect(amount([sun, tue]), 10000);
      expect(
        fq([
          on([sun]),
          on([tue]),
        ]).total,
        10000 + 5000,
      );
    });

    test('입금이 없는 신청인지는 무료 날로 정한다 (금액 0원이 아니라)', () {
      expect(fq([on([sun])]).freeDayOnly, isTrue);
      expect(fq([on([sun, tue])]).freeDayOnly, isFalse);
      // 날짜를 아직 안 고른 사람이 섞여도 무료 날 신청, 가족당 금액 없음
      final mixed = fq([on([sun]), on([])]);
      expect((mixed.freeDayOnly, mixed.total), (true, 0));
      // 100% 할인으로 0원이 된 신청은 아니다
      final discounted = quote(
        rule(),
        start: fri,
        end: tue,
        people: [on([tue])],
        appliedAt: DateTime(2026, 9, 10),
        discount: const Discount(pct: 100),
      );
      expect((discounted.total, discounted.freeDayOnly), (0, false));
    });

    test('당일 금액이 원래 0원인 사람은 (무료) 표시가 붙지 않는다', () {
      final infant = Person(name: '아기', gender: 'M', birthYear: 2025, days: [tue]);
      final l = fq([infant]).lines.single;
      expect((l.amount, l.stay), (0, '당일'));
    });

    test('같은 날짜가 두 번 들어와도 당일은 한 번', () {
      expect(dayVisits([sun, sun, tue]), 2);
    });

    test('무료 날이 없으면 지금과 같다', () {
      expect(
        fq([
          on([sun]),
        ], f: rule(free: [])).total,
        10000 + 5000,
      );
    });

    test('JSON 왕복', () {
      final back = FeeRule.fromJson(rule().toJson());
      expect(back.isFreeDay(sun), isTrue);
      expect(back.isFreeDay(sat), isFalse);
      expect(FeeRule.fromJson({}).freeDays, isEmpty);
    });
  });

  group('숙박비 별도 (PLAN_GATHERING §20)', () {
    // 금~일 2박3일. 성인: 전체 15만 · 하루 6만 · 숙박 1박 3만. 영유아 숙박 0원.
    final fri = DateTime(2026, 10, 9), sat = DateTime(2026, 10, 10);
    final sun = DateTime(2026, 10, 11);
    FeeRule rule({int fullPct = 0, List<DateTime>? free}) => FeeRule(
      full: {AgeGroup.adult: 150000},
      perNight: {AgeGroup.adult: 70000}, // 숙박비 별도면 쓰지 않는다
      dayOnly: {AgeGroup.adult: 60000, AgeGroup.infant: 0},
      lodging: {AgeGroup.adult: 30000, AgeGroup.infant: 0},
      fullDiscountPct: fullPct,
      freeDays: free,
      early: [],
      lodgingSeparate: true,
    );
    Person on(List<DateTime>? days, List<DateTime>? stays, {int y = 1980}) =>
        Person(name: '가', gender: 'M', birthYear: y, days: days, stays: stays);
    QuoteLine line(Person x, {FeeRule? f}) =>
        q(f ?? rule(), [x]).lines.single;

    test('전체 참가 + 숙박 2박 = 15만 + 6만', () {
      final l = line(on(null, [fri, sat]));
      expect((l.participation, l.lodging, l.amount), (150000, 60000, 210000));
      expect(l.stay, '전체 · 숙박 2박');
      expect(l.nights, 2);
    });

    test('전체 참가 + 숙박 안 함 = 15만, 묵는 밤 없음', () {
      final l = line(on(null, []));
      expect((l.participation, l.lodging), (150000, 0));
      expect(l.stay, '전체 · 숙박 안 함');
      expect(l.nights, 0);
    });

    test('토 하루 참가 + 토밤 숙박 = 6만 + 3만', () {
      final l = line(on([sat], [sat]));
      expect((l.participation, l.lodging), (60000, 30000));
      expect(l.stay, '1일 · 숙박 1박');
    });

    test('부분 참가 참가비는 전체 금액을 넘지 않는다 (숙박비는 상한 없음)', () {
      final f = rule()..full[AgeGroup.adult] = 100000;
      final l = line(on([fri, sat], [fri, sat]), f: f);
      expect((l.participation, l.lodging), (100000, 60000));
    });

    test('전체 참석을 비우면 하루 참가 × 일수', () {
      final f = rule()..full.clear();
      expect(line(on(null, []), f: f).participation, 180000);
    });

    test('전체참석 할인은 참가비에만, 사전등록 할인은 합계에', () {
      final l = line(on(null, [fri]), f: rule(fullPct: 10));
      expect((l.participation, l.lodging), (135000, 30000));
      final f = rule()..early = [earlyBird];
      final r = q(f, [on(null, [fri])]);
      expect(r.subtotal, 180000);
      expect(r.earlyDiscount, 18000);
      expect((r.participationTotal, r.lodgingTotal), (150000, 30000));
    });

    test('당일 무료 날: 그 날 참가비는 0, 숙박하면 숙박비는 받는다', () {
      final f = rule(free: [sun]);
      final only = line(on([sun], []), f: f);
      expect((only.amount, only.freeDay), (0, true));
      expect(q(f, [on([sun], [])]).freeDayOnly, isTrue);
      final stay = line(on([sat, sun], [sat]), f: f);
      expect((stay.participation, stay.lodging), (60000, 30000));
      expect(stay.freeDay, isFalse);
    });

    test('영유아는 숙박비 0원', () {
      expect(line(on(null, [fri, sat], y: 2025)).lodging, 0);
    });

    test('숙박을 따로 고르지 않은 신청은 이어진 날 사이 밤으로 센다', () {
      final l = line(on([fri, sat], null));
      expect(l.stayNights, [fri]);
      expect(l.lodging, 30000);
    });

    test('마지막 날 밤·기간 밖 밤은 버린다', () {
      final x = on(null, [sun, DateTime(2026, 10, 1), fri]);
      expect(x.nightsIn(fri, sun, separate: true), [fri]);
    });

    test('끈 집회는 stays 가 있어도 지금 계산 그대로', () {
      {
        final f = planRule();
        expect(f.lodgingSeparate, isFalse, reason: '기본은 꺼짐');
        final family = [
          p('아빠', 1985),
          p('엄마', 1987),
          p('첫째', 2012),
          p('둘째', 2021, checkIn: DateTime(2026, 10, 10)),
        ]..first.stays = [];
        final r = q(f, family);
        expect(r.total, 415000, reason: '§3.3 예시');
        expect(r.separatesLodging, isFalse);
        expect(r.lines.first.nights, 2);
      }
    });

    test('JSON: 켠 집회는 왕복, 끈 집회는 키가 안 생긴다', () {
      final back = FeeRule.fromJson(rule().toJson());
      expect(back.lodgingSeparate, isTrue);
      expect(back.lodging[AgeGroup.adult], 30000);

      final old = planRule().toJson();
      expect(old.containsKey('lodgingSeparate'), isFalse);
      expect(old.containsKey('lodging'), isFalse);
      final reread = FeeRule.fromJson(old);
      expect(reread.lodgingSeparate, isFalse, reason: '키가 없는 기존 집회 = 꺼짐');
      expect(reread.toJson(), old, reason: '기존 집회를 열고 저장해도 그대로');

      // 켰다가 다시 끄면 키가 빠져 예전 JSON 으로 돌아간다. 숙박비 금액은 남는다.
      final off = FeeRule.fromJson(rule().toJson())..lodgingSeparate = false;
      expect(off.toJson().containsKey('lodgingSeparate'), isFalse);
      expect(FeeRule.fromJson(off.toJson()).lodging[AgeGroup.adult], 30000);
    });

    test('Person.stays JSON: 고른 것만 쓰고, 없으면 null', () {
      final x = Person.fromJson(on(null, [fri]).toJson());
      expect(x.stays, [fri]);
      expect(on(null, null).toJson().containsKey('stays'), isFalse);
      expect(Person.fromJson(on(null, null).toJson()).stays, isNull);
    });

    test('isFree: 숙박비 별도면 1박당 대신 숙박비를 본다', () {
      final f = FeeRule(perNight: {AgeGroup.adult: 1000}, lodgingSeparate: true);
      expect(f.isFree, isTrue);
      f.lodging[AgeGroup.adult] = 1000;
      expect(f.isFree, isFalse);
    });
  });
}
