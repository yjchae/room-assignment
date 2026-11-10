import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/models.dart';

// 회비 무료 항목 (FieldSpec.free, PLAN_GATHERING §28.2).
// 금~일 2박3일. 성인: 전체 15만 · 1박 7만 · 당일 3만, 중고등: 전체 12만 · 1박 6만 · 당일 2.5만. 가족당 1만.
final fri = DateTime(2026, 10, 9), sat = DateTime(2026, 10, 10);
final sun = DateTime(2026, 10, 11);
const field = '탈북민';

FeeRule rule({
  int perRegistration = 10000,
  List<EarlyDiscount> early = const [],
  List<DateTime>? freeDays,
  Map<DateTime, Map<AgeGroup, int>>? dayPrices,
  bool separate = false,
}) => FeeRule(
  full: {AgeGroup.adult: 150000, AgeGroup.youth: 120000},
  perNight: {AgeGroup.adult: 70000, AgeGroup.youth: 60000},
  dayOnly: {AgeGroup.adult: 30000, AgeGroup.youth: 25000},
  lodging: separate ? {AgeGroup.adult: 30000, AgeGroup.youth: 20000} : null,
  perRegistration: perRegistration,
  early: early,
  freeDays: freeDays,
  dayPrices: dayPrices,
  lodgingSeparate: separate,
);

/// [free] 면 탈북민 칸에 체크(fieldOn = '예').
Person per(
  String name, {
  int y = 1980,
  bool free = false,
  List<DateTime>? days,
  List<DateTime>? stays,
  String? value,
}) => Person(
  name: name,
  gender: 'M',
  birthYear: y,
  days: days,
  stays: stays,
  extra: {if (free) field: fieldOn, field: ?value},
);

Quote fq(
  List<Person> people, {
  FeeRule? f,
  Iterable<String> freeFields = const [field],
  bool dateless = false,
  DateTime? on,
  Discount discount = Discount.none,
}) => quote(
  f ?? rule(),
  start: fri,
  end: dateless ? fri : sun,
  people: people,
  appliedAt: on ?? DateTime(2026, 9, 10),
  discount: discount,
  dateless: dateless,
  freeFields: freeFields,
);

void main() {
  group('회비 무료 항목 — 일반 집회', () {
    test('체크한 사람만 0원, 나머지는 그대로 + 가족당 금액', () {
      final r = fq([per('아빠'), per('엄마', free: true)]);
      expect(r.lines.map((l) => l.amount), [150000, 0]);
      expect(r.lines.first.exempt, isFalse);
      expect(r.lines.last.exemptBy, field);
      expect(r.lines.last.full, isTrue, reason: '일정은 그대로 적어 둔다');
      expect(r.lines.last.group, AgeGroup.adult);
      expect(r.perRegistration, 10000);
      expect(r.total, 160000);
      expect(r.noPayment, isFalse);
      expect(r.exemptOnly, isFalse);
    });

    test('전원 무료면 가족당 금액도 없고 입금 없음(noPayment)', () {
      final r = fq([per('아빠', free: true), per('딸', y: 2012, free: true)]);
      expect(r.subtotal, 0);
      expect(r.perRegistration, 0);
      expect(r.total, 0);
      expect(r.noPayment, isTrue);
      expect(r.exemptOnly, isTrue);
      expect(r.freeDayOnly, isFalse);
    });

    test('stay 문구 끝에 (항목 무료) — 전체·부분 참석', () {
      final r = fq([
        per('가', free: true),
        per('나', free: true, days: [fri, sat]),
        per('다', free: true, days: [sat]),
      ]);
      expect(r.lines.map((l) => l.stay), [
        '전체(탈북민 무료)',
        '1박(탈북민 무료)',
        '당일(탈북민 무료)',
      ]);
      expect(r.lines.map((l) => l.full), [true, false, false]);
      expect(r.lines.map((l) => l.nights), [2, 1, 0]);
    });

    test("값이 '예'가 아니면 무료가 아니다", () {
      for (final v in ['', '아니오', 'true', ' 예']) {
        final r = fq([per('가', value: v)]);
        expect(r.lines.single.amount, 150000, reason: v);
        expect(r.lines.single.exempt, isFalse);
      }
    });

    test('freeFields 를 넘기지 않으면 지금 계산 그대로', () {
      final r = fq([per('가', free: true)], freeFields: const []);
      expect(r.lines.single.amount, 150000);
      expect(r.lines.single.stay, '전체');
      expect(r.total, 160000);
    });

    test('날짜를 안 고른 사람끼리면 무료 항목이 있어도 가족당 금액은 그대로', () {
      final r = fq([per('가', free: true, days: []), per('나', days: [])]);
      expect(r.subtotal, 0);
      expect(r.noPayment, isFalse);
      expect(r.perRegistration, 10000);
    });

    test('amountOn·totalOn: 무료인 사람은 어느 날이든 0원', () {
      final f = rule();
      final r = fq([
        per('가', free: true),
        per('나', days: [sat]),
      ], f: f);
      expect(r.lines.first.amountOn({fri, sat, sun}, f), 0);
      expect(r.lines.last.amountOn({sat}, f), 30000);
      expect(r.totalOn({fri, sat, sun}, f), 30000);
    });
  });

  group('회비 무료 항목 — 할인', () {
    test('사전등록 할인은 내는 사람 금액에만 걸린다', () {
      final r = fq([
        per('가'),
        per('나', free: true),
      ], f: rule(early: const [(fromDays: 60, toDays: 10, pct: 10)]));
      expect(r.earlyPct, 10);
      expect(r.subtotal, 150000);
      expect(r.earlyDiscount, 15000);
      expect(r.total, 145000);
    });

    test('전원 무료에 지정 할인(원)을 줘도 음수가 아니다', () {
      final r = fq([
        per('가', free: true),
      ], discount: const Discount(amount: 50000, pct: 10));
      expect(r.total, 0);
      expect(r.noPayment, isTrue);
    });
  });

  group('회비 무료 항목 — 무료 날·날짜별 금액', () {
    test('무료 날을 끼고 묵어도 0원', () {
      final r = fq([
        per('가', free: true, days: [sat, sun]),
      ], f: rule(freeDays: [sun]));
      expect(r.lines.single.amount, 0);
      expect(r.lines.single.freeDay, isFalse);
    });

    test('무료 날 당일만 + 무료 항목 체크 = 가족당 금액 없음', () {
      final r = fq([
        per('가', days: [sun]),
        per('나', free: true),
      ], f: rule(freeDays: [sun]));
      expect(r.lines.first.freeDay, isTrue);
      expect(r.noPayment, isTrue);
      expect(r.perRegistration, 0);
      expect(r.total, 0);
    });

    test('날짜별 당일 금액이 있는 날도 0원', () {
      final f = rule(
        dayPrices: {
          sat: {AgeGroup.adult: 50000},
        },
      );
      final r = fq([
        per('가', free: true, days: [sat]),
        per('나', days: [sat]),
      ], f: f);
      expect(r.lines.map((l) => l.amount), [0, 50000]);
      expect(r.lines.first.amountOn({sat}, f), 0);
    });
  });

  group('회비 무료 항목 — 숙박비 별도', () {
    test('참가비·숙박비 모두 0원, 묵는 밤은 그대로', () {
      final r = fq([
        per('가', free: true, days: [fri, sat, sun], stays: [fri, sat]),
        per('나', days: [fri, sat, sun], stays: [fri]),
      ], f: rule(separate: true));
      final x = r.lines.first;
      expect(x.amount, 0);
      expect(x.lodging, 0);
      expect(x.participation, 0);
      expect(x.separate, isTrue);
      expect(x.nights, 2);
      expect(x.stay, '전체 · 숙박 2박(탈북민 무료)');
      expect(r.lines.last.amount, 150000 + 30000);
      expect(r.lodgingTotal, 30000);
      expect(r.participationTotal, 150000);
      expect(x.amountOn({fri, sat, sun}, rule(separate: true)), 0);
    });

    test('전원 무료면 noPayment', () {
      final r = fq([
        per('가', free: true, days: [sat], stays: [sat]),
      ], f: rule(separate: true));
      expect(r.lines.single.stay, '1일 · 숙박 1박(탈북민 무료)');
      expect(r.total, 0);
      expect(r.noPayment, isTrue);
    });
  });

  group('회비 무료 항목 — 날짜 없는 집회', () {
    test('참가 + 무료 = 0원, 다른 참가자는 참가비 + 그룹당', () {
      final r = fq([per('가', free: true), per('나')], dateless: true);
      expect(r.lines.map((l) => l.amount), [0, 150000]);
      expect(r.lines.first.stay, '참가(탈북민 무료)');
      expect(r.lines.first.full, isTrue);
      expect(r.lines.first.dateless, isTrue);
      expect(r.perRegistration, 10000);
      expect(r.noPayment, isFalse);
    });

    test('미참가 + 무료는 문구에 무료를 붙이지 않는다', () {
      final r = fq([per('가', free: true, days: []), per('나')], dateless: true);
      expect(r.lines.first.stay, '미참가');
      expect(r.noShow, isFalse);
      expect(r.noPayment, isFalse);
      expect(r.total, 160000);
    });

    test('참가자 전원이 무료면 그룹당 금액 없음', () {
      final r = fq([
        per('가', free: true),
        per('나', free: true, days: []),
      ], dateless: true);
      expect(r.total, 0);
      expect(r.noPayment, isTrue);
      expect(r.noShow, isFalse);
    });

    test('전원 미참가는 예전처럼 noShow', () {
      final r = fq([per('가', free: true, days: [])], dateless: true);
      expect(r.noShow, isTrue);
      expect(r.noPayment, isTrue);
    });
  });

  group('FieldSpec.free', () {
    test('체크박스·토글에서만 켜진다', () {
      for (final t in FieldType.values) {
        final s = FieldSpec(type: t, free: true);
        expect(
          s.free,
          t == FieldType.check || t == FieldType.toggle,
          reason: t.name,
        );
      }
    });

    test('JSON: 켰을 때만 free 키, 꺼짐이면 키 없음', () {
      expect(const FieldSpec(type: FieldType.check).toJson(), {
        'type': 'check',
      });
      expect(const FieldSpec(type: FieldType.toggle, free: true).toJson(), {
        'type': 'toggle',
        'free': true,
      });
      final back = FieldSpec.fromJson(
        const FieldSpec(type: FieldType.check, free: true).toJson(),
      );
      expect(back.free, isTrue);
      expect(back, const FieldSpec(type: FieldType.check, free: true));
      expect(
        FieldSpec.fromJson({'type': 'check'}).free,
        isFalse,
        reason: '이 기능 전 집회',
      );
      expect(
        FieldSpec.fromJson({'type': 'check', 'free': 'true'}).free,
        isFalse,
      );
    });

    test('형식을 텍스트·숫자·셀렉트로 바꾸면 free 가 꺼지고 JSON 에도 안 남는다', () {
      for (final t in [FieldType.text, FieldType.number, FieldType.select]) {
        final s = FieldSpec(type: t, options: const ['a'], free: true);
        expect(s.free, isFalse);
        expect(s.toJson().containsKey('free'), isFalse, reason: t.name);
        expect(
          FieldSpec.fromJson({'type': t.name, 'free': true}).free,
          isFalse,
        );
      }
      // 같은 형식이면 숨은 플래그와 상관없이 같다 (텍스트는 free 가 뜻이 없다).
      expect(const FieldSpec(free: true), const FieldSpec());
    });

    test('== / hashCode 는 free 를 본다', () {
      const a = FieldSpec(type: FieldType.check);
      const b = FieldSpec(type: FieldType.check, free: true);
      expect(a == b, isFalse);
      expect(
        b.hashCode,
        const FieldSpec(type: FieldType.check, free: true).hashCode,
      );
    });

    test('fieldSpecsToJson/FromJson 왕복', () {
      final specs = {
        field: const FieldSpec(type: FieldType.check, free: true),
        '사역자': const FieldSpec(type: FieldType.toggle),
      };
      final j = fieldSpecsToJson(specs);
      expect(j, {
        field: {'type': 'check', 'free': true},
        '사역자': {'type': 'toggle'},
      });
      expect(fieldSpecsFromJson(j), specs);
    });
  });

  group('Gathering.freeFields·quoteFor', () {
    Gathering g({
      List<String>? formFields,
      Map<String, FieldSpec>? specs,
      bool dateless = false,
    }) => Gathering(
      name: '수련회',
      start: fri,
      end: dateless ? fri : sun,
      dateless: dateless,
      fee: rule(),
      formFields: formFields ?? [field, '교회'],
      fieldSpecs:
          specs ??
          {
            field: const FieldSpec(type: FieldType.check, free: true),
            '교회': const FieldSpec(type: FieldType.select, options: ['가', '나']),
          },
    );

    test('신청서에 묻는 항목(formFields) 중 free 인 것만', () {
      expect(g().freeFields, [field]);
      expect(g(formFields: ['교회']).freeFields, isEmpty, reason: '신청서에서 뺀 항목');
      expect(
        g(specs: {field: const FieldSpec(type: FieldType.text, free: true)})
            .freeFields,
        isEmpty,
        reason: '텍스트 형식은 무료 항목이 아니다',
      );
      expect(
        g(specs: {'없는칸': const FieldSpec(type: FieldType.check, free: true)})
            .freeFields,
        isEmpty,
      );
    });

    test('quoteFor 가 freeFields 를 넘긴다', () {
      final r = g().quoteFor([per('가', free: true)], DateTime(2026, 9, 10));
      expect(r.lines.single.amount, 0);
      expect(r.noPayment, isTrue);
      expect(g().freeFor(r), isTrue);

      final off = g(formFields: ['교회'])
          .quoteFor([per('가', free: true)], DateTime(2026, 9, 10));
      expect(off.lines.single.amount, 150000);
      expect(g(formFields: ['교회']).freeFor(off), isFalse);
    });

    test('quoteFor 날짜 없는 집회', () {
      final x = g(dateless: true);
      final r = x.quoteFor([per('가', free: true)], DateTime(2026, 9, 10));
      expect(r.lines.single.stay, '참가(탈북민 무료)');
      expect(r.total, 0);
    });

    test('fromRow/toRow: field_specs 의 free 가 왕복한다', () {
      final row = g().toRow();
      expect(row['field_specs'], {
        field: {'type': 'check', 'free': true},
        '교회': {
          'type': 'select',
          'options': ['가', '나'],
        },
      });
      final back = Gathering.fromRow({...row, 'id': 'x'});
      expect(back.specOf(field).free, isTrue);
      expect(back.freeFields, [field]);
      expect(back.toRow()['field_specs'], row['field_specs']);
      expect(g().copy().freeFields, [field]);
    });

    test('free 를 안 켠 기존 집회는 field_specs 에 free 키가 생기지 않는다', () {
      final old = {
        'name': '옛 집회',
        'start_date': '2026-10-09',
        'end_date': '2026-10-11',
        'form_fields': [field],
        'field_specs': {
          field: {'type': 'check'},
        },
      };
      final x = Gathering.fromRow(old);
      expect(x.freeFields, isEmpty);
      expect(x.toRow()['field_specs'], {
        field: {'type': 'check'},
      });
    });
  });
}
