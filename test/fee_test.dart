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
      expect(
        fq([
          on([sun]),
        ]).freeDayOnly,
        isTrue,
      );
      expect(
        fq([
          on([sun, tue]),
        ]).freeDayOnly,
        isFalse,
      );
      // 날짜를 아직 안 고른 사람이 섞여도 무료 날 신청, 가족당 금액 없음
      final mixed = fq([
        on([sun]),
        on([]),
      ]);
      expect((mixed.freeDayOnly, mixed.total), (true, 0));
      // 100% 할인으로 0원이 된 신청은 아니다
      final discounted = quote(
        rule(),
        start: fri,
        end: tue,
        people: [
          on([tue]),
        ],
        appliedAt: DateTime(2026, 9, 10),
        discount: const Discount(pct: 100),
      );
      expect((discounted.total, discounted.freeDayOnly), (0, false));
    });

    test('당일 금액이 원래 0원인 사람은 (무료) 표시가 붙지 않는다', () {
      final infant = Person(
        name: '아기',
        gender: 'M',
        birthYear: 2025,
        days: [tue],
      );
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
    QuoteLine line(Person x, {FeeRule? f}) => q(f ?? rule(), [x]).lines.single;

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
      final r = q(f, [
        on(null, [fri]),
      ]);
      expect(r.subtotal, 180000);
      expect(r.earlyDiscount, 18000);
      expect((r.participationTotal, r.lodgingTotal), (150000, 30000));
    });

    test('당일 무료 날: 그 날 참가비는 0, 숙박하면 숙박비는 받는다', () {
      final f = rule(free: [sun]);
      final only = line(on([sun], []), f: f);
      expect((only.amount, only.freeDay), (0, true));
      expect(
        q(f, [
          on([sun], []),
        ]).freeDayOnly,
        isTrue,
      );
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
      final f = FeeRule(
        perNight: {AgeGroup.adult: 1000},
        lodgingSeparate: true,
      );
      expect(f.isFree, isTrue);
      f.lodging[AgeGroup.adult] = 1000;
      expect(f.isFree, isFalse);
    });
  });

  group('날짜 없는 집회 (PLAN_GATHERING §25)', () {
    // 기준일 하나 (start = end).
    final base = DateTime(2026, 10, 9);
    FeeRule rule() => FeeRule(
      full: {AgeGroup.adult: 50000},
      dayOnly: {AgeGroup.youth: 20000}, // 참가비가 비면 하루 금액
      perRegistration: 10000,
    );
    Person going(String n, int y) => p(n, y); // days null = 참가
    Person absent(String n, int y) => p(n, y)..days = [];
    Quote dq(FeeRule f, List<Person> people, {DateTime? to}) => quote(
      f,
      start: base,
      end: to ?? base,
      people: people,
      appliedAt: DateTime(2026, 9, 10),
      dateless: true,
    );

    test('참가 = 참가비, 미참가 = 0원, 그룹당 금액은 붙는다', () {
      final r = dq(rule(), [
        going('아빠', 1985),
        going('아들', 2010),
        absent('할머니', 1950),
      ]);
      expect([for (final l in r.lines) l.amount], [50000, 20000, 0]);
      expect([for (final l in r.lines) l.stay], ['참가', '참가', '미참가']);
      expect(r.perRegistration, 10000);
      expect(r.total, 80000);
      expect((r.noShow, r.noPayment), (false, false));
    });

    test('전원 미참가 → 0원 · 그룹당 0원 · 입금 없음', () {
      final r = dq(rule(), [absent('가', 1985), absent('나', 1990)]);
      expect(r.total, 0);
      expect(r.perRegistration, 0);
      expect((r.noShow, r.noPayment), (true, true));
      final g = Gathering(
        name: 'x',
        start: base,
        end: base,
        fee: rule(),
        dateless: true,
      );
      expect(g.freeFor(g.quoteFor([absent('가', 1985)], base)), isTrue);
      expect(g.freeFor(g.quoteFor([going('가', 1985)], base)), isFalse);
    });

    test('무료 날·숙박비 별도가 남아 있어도 참가 = 참가비 (계산이 무시한다)', () {
      final f = rule()
        ..freeDays = [base]
        ..lodgingSeparate = true
        ..lodging[AgeGroup.adult] = 9999;
      final r = dq(f, [going('가', 1985)]);
      expect(r.lines.single.amount, 50000);
      expect(r.lines.single.freeDay, isFalse);
      expect(r.noPayment, isFalse);
    });

    test('저장된 end 가 기준일과 달라도 참가 = 하루 전체 참석', () {
      final r = dq(rule(), [
        going('가', 1985),
      ], to: base.add(const Duration(days: 2)));
      expect(r.lines.single.amount, 50000);
      expect(r.lines.single.stay, '참가');
    });

    test('Gathering.quoteFor 가 dateless 를 넘긴다', () {
      final g = Gathering(
        name: 'x',
        start: base,
        end: base,
        fee: rule(),
        dateless: true,
      );
      expect(g.quoteFor([absent('가', 1985)], base).lines.single.stay, '미참가');
    });
  });

  group('기존 집회 회귀 — dateless 끄면 한 글자도 안 바뀐다', () {
    test('여러 날 집회: days [] 가 섞여 있어도 금액·그룹당 금액·문구 그대로', () {
      final people = [
        p('전체', 1985),
        p('빈날', 1985)..days = [],
        p('토요일', 1985)..days = [DateTime(2026, 10, 10)],
        p('1박', 1985)..days = [start, DateTime(2026, 10, 10)],
      ];
      for (final r in [
        q(planRule(), people),
        quote(
          planRule(),
          start: start,
          end: end,
          people: people,
          appliedAt: DateTime(2026, 9, 10),
          dateless: false,
        ),
      ]) {
        expect([for (final l in r.lines) l.amount], [150000, 0, 30000, 70000]);
        expect([for (final l in r.lines) l.stay], ['전체', '', '당일', '1박']);
        expect(r.perRegistration, 10000);
        expect(r.earlyPct, 10);
        expect((r.noShow, r.noPayment), (false, false));
      }
    });

    test('여러 날 집회: 전원 days [] 여도 그룹당 금액은 지금처럼 붙는다', () {
      final r = q(planRule(), [p('가', 1985)..days = []]);
      expect(r.perRegistration, 10000);
      expect(r.noShow, isFalse);
    });

    test('하루짜리 집회(dateless 아님): 전체 = full, 문구 "전체", 무료 날 그대로', () {
      final f = planRule()..freeDays = [start];
      final r = q(f, [p('가', 1985), p('나', 2010)], to: start);
      expect([for (final l in r.lines) l.amount], [150000, 120000]);
      expect([for (final l in r.lines) l.stay], ['전체', '전체']);
      expect(r.lines.every((l) => !l.dateless), isTrue);
      // 여러 날 집회에서 무료 날 하루만 고른 당일 신청은 지금처럼 0원·입금 없음.
      final free = q(
        f,
        [
          p('다', 1985)..days = [start],
        ],
        from: start,
        to: end,
      );
      expect(free.freeDayOnly, isTrue);
      expect(free.noPayment, isTrue);
    });

    test('기존 집회 freeFor 는 그대로 (무료 날 당일만 → 입금 없음)', () {
      final g = Gathering(
        name: 'x',
        start: start,
        end: end,
        fee: planRule()..freeDays = [start],
      );
      expect(
        g.freeFor(
          g.quoteFor([
            p('가', 1985)..days = [start],
          ], start),
        ),
        isTrue,
      );
      expect(g.freeFor(g.quoteFor([p('가', 1985)], start)), isFalse);
    });
  });

  group('날짜별 금액', () {
    final fri = start, sat = DateTime(2026, 10, 10), sun = end;
    Person on(List<DateTime>? days) =>
        Person(name: '김', gender: 'M', birthYear: 1980, days: days);
    Quote of(FeeRule f, List<Person> ps, {Discount d = Discount.none}) => quote(
      f,
      start: start,
      end: end,
      people: ps,
      appliedAt: DateTime(2026, 9, 25), // 사전등록 구간 밖
      discount: d,
    );

    test('전체 참석도 그 밤 1박 요금, 마지막 날은 0원, 모두 고르면 정액을 안 넘는다', () {
      final f = planRule();
      final l = of(f, [on(null)]).lines.single;
      expect(l.amountOn({sat}, f), 70000);
      expect(l.amountOn({sun}, f), 0);
      expect(l.amountOn({fri, sat, sun}, f), 140000);
    });

    test('당일은 당일 요금, 무료 날은 0원, 안 오는 날은 0원', () {
      final f = planRule()..freeDays = [sun];
      expect(
        of(f, [
          on([sat]),
        ]).lines.single.amountOn({sat}, f),
        30000,
      );
      expect(
        of(f, [
          on([sat]),
        ]).lines.single.amountOn({fri}, f),
        0,
      );
      expect(
        of(f, [
          on([sun]),
        ]).lines.single.amountOn({sun}, f),
        0,
      );
    });

    test('숙박비 별도: 참가일 하루 참가 + 묵는 밤 숙박비', () {
      final f = planRule()
        ..lodgingSeparate = true
        ..lodging = {AgeGroup.adult: 40000};
      final l = of(f, [
        on(null)..stays = [fri],
      ]).lines.single;
      expect(l.amountOn({fri}, f), 70000);
      expect(l.amountOn({sat}, f), 30000);
    });

    test('신청 금액: 지정 할인(%)은 적용, 그룹당 금액은 빼고, 합계는 넘지 않는다', () {
      final f = planRule();
      final half = of(f, [on(null)], d: const Discount(pct: 50));
      expect(half.totalOn({sat}, f), 35000);
      final zero = of(f, [on(null)], d: const Discount(amount: 999999));
      expect(zero.totalOn({sat}, f), 0);
    });
  });

  group('날짜별 당일 금액 (PLAN_GATHERING §27.1)', () {
    // 금~화 4박5일. 성인: 전체 10만 · 1박 3만 · 당일 1만. 일요일은 무료 날.
    final fri = DateTime(2026, 10, 9), sat = DateTime(2026, 10, 10);
    final sun = DateTime(2026, 10, 11), mon = DateTime(2026, 10, 12);
    final tue = DateTime(2026, 10, 13);
    FeeRule rule({Map<DateTime, Map<AgeGroup, int>>? prices}) => FeeRule(
      full: {AgeGroup.adult: 100000},
      perNight: {AgeGroup.adult: 30000},
      dayOnly: {AgeGroup.adult: 10000, AgeGroup.youth: 4000},
      perRegistration: 5000,
      freeDays: [sun],
      dayPrices:
          prices ??
          {
            sat: {AgeGroup.adult: 7000},
            sun: {AgeGroup.adult: 5000}, // 무료 날이 이긴다
            mon: {AgeGroup.adult: 0},
          },
    );
    Person on(List<DateTime> days) =>
        Person(name: '가', gender: 'M', birthYear: 1980, days: days);
    Quote of(FeeRule f, List<DateTime> days) =>
        q(f, [on(days)], from: fri, to: tue, on: DateTime(2026, 10, 1));

    test('우선순위: 무료 날 > 날짜 지정 금액 > 기본 당일 금액', () {
      final f = rule();
      expect(f.dayPriceOn(AgeGroup.adult, fri), 10000, reason: '지정 없음 = 기본');
      expect(f.dayPriceOn(AgeGroup.adult, sat), 7000, reason: '지정 금액');
      expect(f.dayPriceOn(AgeGroup.adult, sun), 0, reason: '무료 날이 지정 금액보다 먼저');
      expect(f.dayPriceOn(AgeGroup.adult, mon), 0, reason: '0원 지정');
      expect(
        f.dayPriceOn(AgeGroup.youth, sat),
        4000,
        reason: '그 구분은 지정 안 함 = 기본',
      );
      expect(f.dayPriceOn(AgeGroup.child, sat), 0, reason: '기본도 없으면 0원');
      expect(
        f.dayPriceOn(AgeGroup.adult, DateTime(2026, 10, 10, 15)),
        7000,
        reason: '시각은 보지 않는다',
      );
      expect(f.pricesOn(fri), isNull);
    });

    test('보통 집회: 혼자 고른 날마다 그 날 금액, 1박·전체 참석은 그대로', () {
      final f = rule();
      expect(of(f, [sat]).lines.single.amount, 7000);
      expect(
        of(f, [fri, tue]).lines.single.amount,
        20000,
        reason: '지정 없는 날 = 기본 1만',
      );
      expect(of(f, [sat, mon]).lines.single.amount, 7000);
      expect(of(f, [fri, sat]).lines.single.amount, 30000, reason: '묵으면 1박 요금');
      expect(of(f, [fri, sat, sun, mon, tue]).lines.single.amount, 100000);
      // 같은 사람 금액을 날짜로 쪼갤 때도 그 날 금액
      final l = of(f, [sat, mon]).lines.single;
      expect(l.amountOn({sat}, f), 7000);
      expect(l.amountOn({mon}, f), 0);
    });

    test('0원으로 지정한 날은 무료 날이 아니다 (그룹당 금액은 붙는다)', () {
      final f = rule();
      final zero = of(f, [mon]);
      expect(zero.lines.single.amount, 0);
      expect(zero.lines.single.freeDay, isFalse);
      expect(zero.freeDayOnly, isFalse);
      expect(zero.total, 5000);
      final free = of(f, [sun]);
      expect(free.lines.single.freeDay, isTrue);
      expect(free.total, 0);
    });

    test('부분 참석 상한: 날짜 금액을 높여도 전체 참석 금액을 넘지 않는다', () {
      final f = rule(
        prices: {
          fri: {AgeGroup.adult: 90000},
          tue: {AgeGroup.adult: 90000},
        },
      );
      expect(of(f, [fri, tue]).lines.single.amount, 100000);
    });

    test('숙박비 별도: 참가일마다 그 날 하루 참가 금액 + 숙박비, 상한 그대로', () {
      final fr = DateTime(2026, 10, 9), sa = DateTime(2026, 10, 10);
      FeeRule sep(Map<DateTime, Map<AgeGroup, int>> prices) => FeeRule(
        full: {AgeGroup.adult: 150000},
        dayOnly: {AgeGroup.adult: 60000},
        lodging: {AgeGroup.adult: 30000},
        lodgingSeparate: true,
        dayPrices: prices,
      );
      QuoteLine line(FeeRule f, List<DateTime>? days, List<DateTime> stays) =>
          q(f, [
            Person(
              name: '가',
              gender: 'M',
              birthYear: 1980,
              days: days,
              stays: stays,
            ),
          ], on: DateTime(2026, 10, 1)).lines.single;
      final f = sep({
        sa: {AgeGroup.adult: 20000},
      });
      final l = line(f, [fr, sa], [fr]);
      expect((l.participation, l.lodging, l.amount), (80000, 30000, 110000));
      expect(l.amountOn({sa}, f), 20000);
      expect(
        line(f, null, [fr, sa]).participation,
        150000,
        reason: '전체 참가는 정액 그대로',
      );
      final high = sep({
        fr: {AgeGroup.adult: 100000},
        sa: {AgeGroup.adult: 100000},
      });
      expect(
        line(high, [fr, sa], []).participation,
        150000,
        reason: '전체 참석 금액이 상한',
      );
    });

    test('날짜 없는 집회는 날짜별 금액을 보지 않는다', () {
      final f = FeeRule(
        full: {AgeGroup.adult: 50000},
        dayPrices: {
          fri: {AgeGroup.adult: 1000},
        },
      );
      final r = quote(
        f,
        start: fri,
        end: fri,
        people: [on([])..days = null],
        appliedAt: fri,
        dateless: true,
      );
      expect(r.lines.single.amount, 50000);
    });

    test('isFree 는 날짜별 금액도 본다', () {
      expect(
        FeeRule(
          dayPrices: {
            sat: {AgeGroup.adult: 5000},
          },
        ).isFree,
        isFalse,
      );
      expect(
        FeeRule(
          dayPrices: {
            sat: {AgeGroup.adult: 0},
          },
        ).isFree,
        isTrue,
      );
    });

    test('JSON: 날짜 키는 ymd, 값 있는 날만 쓰고 그대로 되읽는다', () {
      final f = rule()..dayPrices[tue] = {};
      final j = f.toJson();
      expect(j['dayPrices'], {
        '2026-10-10': {'adult': 7000},
        '2026-10-11': {'adult': 5000},
        '2026-10-12': {'adult': 0},
      });
      final back = FeeRule.fromJson(j);
      expect(back.dayPriceOn(AgeGroup.adult, sat), 7000);
      expect(back.dayPriceOn(AgeGroup.adult, mon), 0);
      expect(back.pricesOn(tue), isNull);
      expect(FeeRule.fromJson(back.toJson()).toJson(), j);
      expect(FeeRule().toJson().containsKey('dayPrices'), isFalse);
      expect(
        FeeRule.fromJson({
          'dayPrices': {
            '2026-10-10': {'adult': 1000, 'nope': 5},
            '깨짐': {'adult': 1},
            '2026-10-11': {},
          },
        }).dayPrices,
        {
          DateTime(2026, 10, 10): {AgeGroup.adult: 1000},
        },
        reason: '깨진 날짜·모르는 구분·빈 날은 버린다',
      );
    });
  });

  group('연령 구분 추가 (PLAN_GATHERING §27.3)', () {
    test('기본 구분: AgeGroup 은 id 로 같고, groups 기본은 다섯', () {
      expect(const AgeGroup('adult', '어른'), AgeGroup.adult);
      expect(const AgeGroup('adult', '어른').hashCode, AgeGroup.adult.hashCode);
      expect(FeeRule().groups, AgeGroup.values);
      expect(FeeRule(groups: []).groups, AgeGroup.values, reason: '비우면 기본');
      expect(AgeGroup.adult.isBuiltIn, isTrue);
      expect(AgeGroup.newId(), matches(RegExp(r'^c[0-9a-z]{6}$')));
      expect(AgeGroup.newId(), isNot(AgeGroup.newId()));
    });

    test('기존 회비 JSON 은 한 글자도 안 바뀐다 (groups·dayPrices 키 없음)', () {
      final old = planRule().toJson();
      expect(old.keys, [
        'full',
        'perNight',
        'dayOnly',
        'minAge',
        'perRegistration',
        'fullDiscountPct',
        'early',
        'freeDays',
      ]);
      expect(FeeRule.fromJson(old).toJson(), old);
      // 서버에 저장돼 있던 모양 그대로 (minAge 를 일부만 가진 옛 JSON 포함)
      final saved = {
        'full': {'adult': 150000, 'youth': 120000},
        'perNight': {'adult': 70000},
        'dayOnly': {'adult': 30000},
        'minAge': {'adult': 20},
        'perRegistration': 10000,
        'fullDiscountPct': 0,
        'early': [],
        'freeDays': ['2026-10-11'],
      };
      expect(FeeRule.fromJson(saved).toJson(), {
        ...saved,
        'minAge': {
          'adult': 20,
          'youth': 13,
          'child': 7,
          'kinder': 4,
          'infant': 0,
        },
      });
    });

    test('새 구분: groupOf · quote · summary 순서', () {
      final f = planRule(early: []);
      final senior = f.addGroup('장년', 60);
      f.full[senior] = 80000;
      expect(senior.name, matches(RegExp(r'^c[0-9a-z]{6}$')));
      expect(senior.isBuiltIn, isFalse);
      expect(f.groupOf(65), senior);
      expect(f.groupOf(60), senior);
      expect(f.groupOf(59), AgeGroup.adult);
      expect(f.groupOf(-1), AgeGroup.infant);

      final people = [p('형', 1980), p('할머니', 1960), p('동생', 1985)];
      var r = q(f, people);
      expect(r.lines.map((l) => l.group).toList(), [
        AgeGroup.adult,
        senior,
        AgeGroup.adult,
      ]);
      expect(r.lines[1].amount, 80000);
      expect(r.summary, '성인 2 · 장년 1', reason: '표 순서(맨 끝에 더함)');

      // 표 맨 앞으로 옮기고 성인 이름을 바꾸면 그 순서·이름으로 센다
      f.groups
        ..remove(senior)
        ..insert(0, senior);
      f.groups[1] = AgeGroup.adult.withLabel('어른');
      r = q(f, people);
      expect(r.summary, '장년 1 · 어른 2');
      expect(r.lines.first.group.label, '어른');
      expect(f.labelOf(AgeGroup.adult), '어른');
      expect(r.lines.first.amount, 150000, reason: '이름만 바꾼 구분은 금액 그대로');
    });

    test('groups JSON 왕복: 기본과 다를 때만 쓴다', () {
      final f = planRule();
      final senior = f.addGroup('장년', 60);
      f.full[senior] = 80000;
      f.dayPrices[DateTime(2026, 10, 10)] = {senior: 5000};
      final j = f.toJson();
      expect(j['groups'], [
        for (final g in AgeGroup.values) {'id': g.name, 'label': g.label},
        {'id': senior.name, 'label': '장년'},
      ]);
      final back = FeeRule.fromJson(j);
      expect(
        back.groups.map((g) => (g.name, g.label)),
        f.groups.map((g) => (g.name, g.label)),
      );
      expect(back.full[senior], 80000);
      expect(back.startAge(senior), 60);
      expect(back.dayPriceOn(senior, DateTime(2026, 10, 10)), 5000);
      expect(FeeRule.fromJson(back.toJson()).toJson(), j);

      // 이름만 바꿔도 기본과 다르다
      final renamed = planRule()..groups[0] = AgeGroup.adult.withLabel('어른');
      expect(renamed.toJson()['groups'], isNotNull);
      expect(FeeRule.fromJson(renamed.toJson()).labelOf(AgeGroup.adult), '어른');
      // 기본으로 되돌리면 키가 사라진다
      expect(
        (renamed..groups[0] = AgeGroup.adult).toJson().containsKey('groups'),
        isFalse,
      );
    });

    test('groups JSON 읽기: 없는 구분의 금액은 버리고, 더한 구분의 시작 나이가 없으면 0', () {
      final f = FeeRule.fromJson({
        'groups': [
          {'id': 'adult', 'label': '성인'},
          {'id': 'cabc123', 'label': '어린이'},
          {'id': 'cabc123', 'label': '겹침'},
          {'id': '', 'label': '빈 id'},
        ],
        'full': {'adult': 1000, 'youth': 500, 'cabc123': 300},
        'minAge': {'adult': 20},
      });
      const kid = AgeGroup('cabc123', '어린이');
      expect(f.groups.map((g) => g.label), ['성인', '어린이']);
      expect(f.full, {AgeGroup.adult: 1000, kid: 300});
      expect(f.minAge, {AgeGroup.adult: 20, kid: 0});
      expect(f.groupOf(19), kid);
      expect(f.groupOf(20), AgeGroup.adult);
      expect(f.toJson()['full'], {'adult': 1000, 'cabc123': 300});
      // 기본 구분인데 이름이 비었으면 기본 이름
      expect(
        FeeRule.fromJson({
          'groups': [
            {'id': 'youth'},
          ],
        }).labelOf(AgeGroup.youth),
        '중고등',
      );
    });

    test('기본 구분을 빼면: 남은 것 중 시작 나이가 가장 낮은 구분으로 떨어진다', () {
      final f = planRule();
      expect(f.removeGroup(AgeGroup.infant), isTrue);
      expect(f.groups, isNot(contains(AgeGroup.infant)));
      expect(f.full.containsKey(AgeGroup.infant), isFalse, reason: '금액도 지운다');
      expect(f.groupOf(2), AgeGroup.kinder);
      expect(f.groupOf(-3), AgeGroup.kinder);
      expect(q(f, [p('아기', 2025)]).lines.single.group, AgeGroup.kinder);
      expect(f.toJson()['minAge'], {
        'adult': 19,
        'youth': 13,
        'child': 7,
        'kinder': 4,
      });

      final two = FeeRule(groups: [AgeGroup.adult, AgeGroup.youth]);
      expect(two.groupOf(5), AgeGroup.youth, reason: '어디에도 안 걸리면 가장 낮은 구분');
      expect(two.removeGroup(AgeGroup.child), isFalse, reason: '없는 구분');
      expect(two.removeGroup(AgeGroup.youth), isTrue);
      expect(two.removeGroup(AgeGroup.adult), isFalse, reason: '마지막 하나는 남긴다');
      expect(two.groupOf(0), AgeGroup.adult);
    });
  });

  group('회비 안내 문구 Gathering.feeNote (PLAN_GATHERING §27.2)', () {
    Gathering g0() => Gathering(name: '집회', start: start, end: end);

    test('칸이 없는 DB 에서 읽었고 값도 없으면 fee_note 를 보내지 않는다', () {
      expect(g0().toRow().containsKey('fee_note'), isFalse);
      final old = Gathering.fromRow({...g0().toRow(), 'id': 'x'});
      expect(old.toRow().containsKey('fee_note'), isFalse);
      expect(old.copy().toRow().containsKey('fee_note'), isFalse);
    });

    test('값이 있으면 보내고, 칸이 있는 DB 에서 읽었으면 null 도 보낸다', () {
      expect((g0()..feeNote = '나이는\n학년으로').toRow()['fee_note'], '나이는\n학년으로');
      final read = Gathering.fromRow({
        ...g0().toRow(),
        'id': 'x',
        'fee_note': null,
      });
      expect(read.feeNote, isNull);
      expect(read.toRow().containsKey('fee_note'), isTrue);
      expect(read.toRow()['fee_note'], isNull);
      expect(
        read.copy().toRow().containsKey('fee_note'),
        isTrue,
        reason: 'copy 도 칸 표시를 잇는다',
      );
    });

    test('fromRow·copy 왕복, 공백뿐이면 null(자동 문구)', () {
      final g = Gathering.fromRow({
        ...g0().toRow(),
        'id': 'x',
        'fee_note': ' 문의: 총무 \n',
      });
      expect(g.feeNote, ' 문의: 총무 \n', reason: '내용은 다듬지 않는다');
      expect(g.copy().feeNote, ' 문의: 총무 \n');
      expect(g.toRow()['fee_note'], ' 문의: 총무 \n');
      expect((g..feeNote = '  \n').toRow()['fee_note'], isNull);
      expect(
        Gathering.fromRow({...g0().toRow(), 'fee_note': ''}).feeNote,
        isNull,
      );
    });
  });
}
