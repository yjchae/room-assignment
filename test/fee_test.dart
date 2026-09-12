import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';

// 기획서 §3.3 예시 집회: 2026-10-09(금) ~ 10-11(일), 2박3일
final start = DateTime(2026, 10, 9);
final end = DateTime(2026, 10, 11);
final earlyBird = (
  from: DateTime(2026, 9, 1),
  to: DateTime(2026, 9, 20),
  pct: 10,
);

/// 기획서 §3.2 금액표.
FeeRule planRule({
  int perRegistration = 10000,
  int fullDiscountPct = 0,
  List<PeriodDiscount>? periods,
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
  periods: periods ?? [earlyBird],
);

Person p(String name, int birthYear, {DateTime? checkIn, DateTime? checkOut}) =>
    Person(
      name: name,
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
    expect(r.periodDiscount, 45000);
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
    final r = q(planRule(perRegistration: 0, periods: []), [p('아기', 2025)]);
    expect(r.lines.single.group, AgeGroup.infant);
    expect(r.total, 0);
  });

  test('일정이 집회 기간 전체면 전체 참석 — 기간 밖 날짜는 잘라서 본다', () {
    final r = q(planRule(periods: []), [
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
    final r = q(planRule(periods: []), [
      p('당일', 1990, checkIn: day, checkOut: day),
    ]);
    expect(r.lines.single.nights, 0);
    expect(r.lines.single.amount, 30000);
  });

  test('부분 참석 금액은 전체 참석 금액을 넘지 않는다', () {
    // 3박 집회, 1박 80,000 × 2박 = 160,000 > 전체 150,000 → 150,000
    final f = planRule(periods: [])..perNight[AgeGroup.adult] = 80000;
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

  test('전체 정액을 비우면 1박당 × 박수, 전체참석 할인 → 기간 할인 순서로 겹쳐 적용', () {
    final f = planRule(fullDiscountPct: 10)..full.remove(AgeGroup.adult);
    final r = q(f, [
      p('전체', 1990), // 70,000 × 2박 = 140,000 → 10% 할인 126,000
      p('1박', 1990, checkIn: DateTime(2026, 10, 10)), // 70,000 (전체참석 할인 없음)
    ]);
    expect(r.lines.map((l) => l.amount), [126000, 70000]);
    expect(r.subtotal, 196000);
    expect(r.total, 196000 * 90 ~/ 100 + 10000); // 186,400
  });

  test('기간 할인: 양 끝 날짜 포함, 겹치면 큰 쪽', () {
    final f = planRule(
      perRegistration: 0,
      periods: [
        earlyBird,
        (from: DateTime(2026, 9, 15), to: DateTime(2026, 9, 16), pct: 20),
      ],
    );
    final people = [p('a', 1990)];
    expect(q(f, people, on: DateTime(2026, 9, 1)).periodPct, 10);
    expect(q(f, people, on: DateTime(2026, 9, 20, 23, 59)).periodPct, 10);
    expect(q(f, people, on: DateTime(2026, 9, 21)).periodPct, 0);
    expect(q(f, people, on: DateTime(2026, 9, 15)).periodPct, 20);
    expect(q(f, people, on: DateTime(2026, 8, 31)).total, 150000);
  });

  test('원 미만 버림', () {
    final f = FeeRule(full: {AgeGroup.adult: 33333}, periods: [earlyBird]);
    final r = q(f, [p('a', 1990)]);
    expect(r.total, 29999); // 33,333 × 0.9 = 29,999.7
    expect(r.subtotal - r.periodDiscount, r.total);
  });

  test('참석자가 없으면 그룹당 금액도 붙지 않는다', () {
    final r = q(planRule(), []);
    expect(r.total, 0);
  });

  test('할인율이 범위를 벗어나도 음수 금액이 나오지 않는다', () {
    final f = planRule(
      fullDiscountPct: 150,
      periods: [
        (from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30), pct: 200),
      ],
    );
    final r = q(f, [p('a', 1990)]);
    expect(r.lines.single.amount, 0);
    expect(r.total, 10000); // 그룹당 금액만
  });
}
