/// 집회 신청 회비 계산. 신청 웹과 관리자 앱이 같은 코드를 쓴다 —
/// 웹 빌드에도 들어가므로 dart:io / flutter 를 import 하지 않는다.
library;

import 'dart:math' as math;

enum AgeGroup {
  adult('성인'),
  youth('중고등'),
  child('초등'),
  kinder('유치'),
  infant('영유아');

  const AgeGroup(this.label);
  final String label;
}

/// 기간 할인 한 구간. [from]~[to] 사이(양 끝 포함)에 신청하면 [pct]% 할인.
typedef PeriodDiscount = ({DateTime from, DateTime to, int pct});

class FeeRule {
  FeeRule({
    Map<AgeGroup, int>? full,
    Map<AgeGroup, int>? perNight,
    Map<AgeGroup, int>? dayOnly,
    Map<AgeGroup, int>? minAge,
    this.perRegistration = 0,
    this.fullDiscountPct = 0,
    List<PeriodDiscount>? periods,
  }) : full = full ?? {},
       perNight = perNight ?? {},
       dayOnly = dayOnly ?? {},
       minAge = minAge ?? {...defaultMinAge},
       periods = periods ?? [];

  /// 전체 참석 정액. 키가 없으면 1박당 × 전체 박수.
  Map<AgeGroup, int> full;

  /// 부분 참석 1박당. 키가 없으면 0원.
  Map<AgeGroup, int> perNight;

  /// 당일(무박). 키가 없으면 0원.
  Map<AgeGroup, int> dayOnly;

  /// 구분이 시작되는 연 나이 (집회 연도 − 출생연도).
  Map<AgeGroup, int> minAge;

  /// 신청 1건(가족·그룹)당 더하는 금액.
  int perRegistration;

  /// 전체 참석자 1인 금액에 적용하는 할인율(%).
  int fullDiscountPct;

  /// 신청일 기준 할인. 구간이 겹치면 큰 쪽 하나만.
  List<PeriodDiscount> periods;

  static const defaultMinAge = {
    AgeGroup.adult: 19,
    AgeGroup.youth: 13,
    AgeGroup.child: 7,
    AgeGroup.kinder: 4,
    AgeGroup.infant: 0,
  };

  /// 연 나이 → 구분. 시작 나이가 높은 구분부터 보고 처음 걸리는 것.
  /// 어디에도 안 걸리면(출생연도 오타로 음수 등) 영유아.
  AgeGroup groupOf(int age) {
    final order = [...minAge.entries]
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in order) {
      if (age >= e.value) return e.key;
    }
    return AgeGroup.infant;
  }

  /// [on] 날짜에 신청했을 때의 기간 할인율.
  int periodPctOn(DateTime on) {
    final d = _day(on);
    return periods
        .where((p) => !d.isBefore(_day(p.from)) && !d.isAfter(_day(p.to)))
        .fold(0, (m, p) => math.max(m, p.pct));
  }
}

/// 신청서의 참석자 한 명. 일정이 null 이면 집회 시작일/종료일.
class Person {
  Person({
    required this.name,
    required this.birthYear,
    this.checkIn,
    this.checkOut,
  });

  String name;
  int birthYear;
  DateTime? checkIn, checkOut;
}

class QuoteLine {
  const QuoteLine(this.person, this.group, this.nights, this.full, this.amount);
  final Person person;
  final AgeGroup group;

  /// 이 사람이 묵는 박수. 0 = 당일.
  final int nights;
  final bool full;
  final int amount;
}

class Quote {
  const Quote(this.lines, this.periodPct, this.perRegistration);
  final List<QuoteLine> lines;
  final int periodPct;
  final int perRegistration;

  int get subtotal => lines.fold(0, (s, l) => s + l.amount);

  /// 할인 후 금액의 원 미만을 버리도록 계산한다 (할인액 쪽이 올림).
  int get periodDiscount => subtotal - subtotal * (100 - periodPct) ~/ 100;

  int get total => subtotal - periodDiscount + perRegistration;
}

/// 신청 합계와 내역. 신청 웹·조회·관리자 화면 전부 이것 하나를 부른다.
/// [appliedAt] = 신청일 (기간 할인 기준).
///
/// - 일정이 집회 기간 전체면 전체 참석(정액), 아니면 부분 참석(1박당 × 박수, 0박이면 당일).
/// - 일정은 집회 기간 안으로 잘라서 본다.
/// - 부분 참석 금액은 전체 참석자가 내는 금액을 넘지 않는다.
/// - 참석자가 없으면 그룹당 금액도 붙지 않는다 (빈 신청서에 금액이 뜨지 않게).
Quote quote(
  FeeRule fee, {
  required DateTime start,
  required DateTime end,
  required List<Person> people,
  required DateTime appliedAt,
}) {
  final s = _day(start);
  final e = _day(end).isBefore(s) ? s : _day(end);
  final allNights = _nights(s, e);
  final fullPct = fee.fullDiscountPct.clamp(0, 100);

  QuoteLine line(Person p) {
    final g = fee.groupOf(s.year - p.birthYear);
    var from = _day(p.checkIn ?? s), to = _day(p.checkOut ?? e);
    if (from.isBefore(s)) from = s;
    if (from.isAfter(e)) from = e;
    if (to.isAfter(e)) to = e;
    if (to.isBefore(from)) to = from;

    final nightly = fee.perNight[g] ?? 0;
    final day = fee.dayOnly[g] ?? 0;
    final fullBase = fee.full[g] ?? (allNights > 0 ? nightly * allNights : day);
    final fullPrice = fullBase * (100 - fullPct) ~/ 100;

    final n = _nights(from, to);
    final isFull = from == s && to == e;
    final amount = isFull
        ? fullPrice
        : math.min(n > 0 ? nightly * n : day, fullPrice);
    return QuoteLine(p, g, n, isFull, amount);
  }

  final lines = people.map(line).toList();
  return Quote(
    lines,
    lines.isEmpty ? 0 : fee.periodPctOn(appliedAt).clamp(0, 100),
    lines.isEmpty ? 0 : fee.perRegistration,
  );
}

/// 날짜만 남긴 UTC. 일수 계산이 서머타임 등에 흔들리지 않게 UTC 로 뺀다.
DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _nights(DateTime from, DateTime to) => to.difference(from).inDays;
