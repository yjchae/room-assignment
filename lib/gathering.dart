/// 집회·신청 모델과 회비 계산. 신청 웹과 관리자 앱이 같은 코드를 쓴다 —
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

/// 사전등록 할인 한 구간. 집회 시작 [fromDays]일 전 ~ [toDays]일 전(양 끝 포함)에
/// 신청하면 [pct]% 할인. fromDays ≥ toDays.
typedef EarlyDiscount = ({int fromDays, int toDays, int pct});

class FeeRule {
  FeeRule({
    Map<AgeGroup, int>? full,
    Map<AgeGroup, int>? perNight,
    Map<AgeGroup, int>? dayOnly,
    Map<AgeGroup, int>? minAge,
    this.perRegistration = 0,
    this.fullDiscountPct = 0,
    List<EarlyDiscount>? early,
  }) : full = full ?? {},
       perNight = perNight ?? {},
       dayOnly = dayOnly ?? {},
       minAge = minAge ?? {...defaultMinAge},
       early = early ?? [];

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

  /// 사전등록 할인. 신청일이 집회 시작 며칠 전인지로 본다. 구간이 겹치면 큰 쪽 하나만.
  List<EarlyDiscount> early;

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

  /// [start] 에 시작하는 집회에 [on] 날짜에 신청했을 때의 사전등록 할인율.
  int earlyPctOn(DateTime on, DateTime start) {
    final d = _nights(_day(on), _day(start));
    return early
        .where((e) => d <= e.fromDays && d >= e.toDays)
        .fold(0, (m, e) => math.max(m, e.pct));
  }

  /// 받는 돈이 하나도 없다 (모든 금액이 0 이거나 비어 있음). 신청 웹에서 회비·계좌를 숨긴다.
  bool get isFree => [
    ...full.values,
    ...perNight.values,
    ...dayOnly.values,
    perRegistration,
  ].every((v) => v == 0);

  Map<String, dynamic> toJson() => {
    'full': _groupsOut(full),
    'perNight': _groupsOut(perNight),
    'dayOnly': _groupsOut(dayOnly),
    'minAge': _groupsOut(minAge),
    'perRegistration': perRegistration,
    'fullDiscountPct': fullDiscountPct,
    'early': [
      for (final e in early)
        {'fromDays': e.fromDays, 'toDays': e.toDays, 'pct': e.pct},
    ],
  };

  factory FeeRule.fromJson(Object? json) {
    final j = json is Map ? json : const {};
    return FeeRule(
      full: _groupsIn(j['full']),
      perNight: _groupsIn(j['perNight']),
      dayOnly: _groupsIn(j['dayOnly']),
      minAge: {...defaultMinAge, ..._groupsIn(j['minAge'])},
      perRegistration: _int(j['perRegistration']),
      fullDiscountPct: _int(j['fullDiscountPct']),
      early: [
        for (final e in (j['early'] is List ? j['early'] as List : []))
          if (e is Map)
            (
              fromDays: _int(e['fromDays']),
              toDays: _int(e['toDays']),
              pct: _int(e['pct']),
            ),
      ],
    );
  }
}

/// 신청서의 참석자 한 명. 일정은 [daysIn] 으로 읽는다.
class Person {
  Person({
    String? id,
    required this.name,
    required this.gender,
    required this.birthYear,
    this.relation = '본인',
    this.days,
    this.checkIn,
    this.checkOut,
    this.phone,
    this.cell,
    String? zone,
    this.minister = false,
    this.church,
    Map<String, String>? extra,
  }) : id = id ?? newPersonId(),
       extra = extra ?? {},
       _zone = zone?.toUpperCase();

  /// 신청 웹에서 만들어져 관리자 앱의 참석자 id 로 그대로 이어진다.
  String id;
  String name;
  String gender; // 'M' | 'F' | '' (운영자가 성별 칸을 뺌)
  int birthYear;
  String relation;

  /// 참석하는 날 (신청 웹의 날짜 체크). null = 전체 참석.
  List<DateTime>? days;

  /// 예전 신청서 형식(도착일~출발일). [days] 가 없을 때만 본다. null 이면 집회 시작일/종료일.
  DateTime? checkIn, checkOut;
  String? phone, cell;

  /// 존. 신청 웹에서 'a존'으로 써도 'A존'으로 저장·표시한다 (예전에 소문자로 들어온 신청도 읽을 때).
  String? get zone => _zone;
  set zone(String? v) => _zone = v?.toUpperCase();
  String? _zone;

  /// 신청서의 "사역자" 체크.
  bool minister;

  /// 사역자가 섬기는 교회 이름. 사역자를 체크하면 필수.
  String? church;

  /// 사용자 정의 항목(교회·직분 등) 값.
  Map<String, String> extra;

  /// 집회 [start]~[end] 중 참석하는 날 (정렬, 기간 밖은 버린다).
  List<DateTime> daysIn(DateTime start, DateTime end) {
    final s = _day(start), e = _day(end);
    Iterable<DateTime> picked;
    if (days != null) {
      picked = days!.map(_day);
    } else {
      var from = _day(checkIn ?? s), to = _day(checkOut ?? e);
      if (from.isBefore(s)) from = s;
      if (from.isAfter(e)) from = e;
      if (to.isAfter(e)) to = e;
      if (to.isBefore(from)) to = from;
      picked = [
        for (var i = 0; i <= _nights(from, to); i++)
          from.add(Duration(days: i)),
      ];
    }
    final out = {
      for (final d in picked)
        if (!d.isBefore(s) && !d.isAfter(e)) d,
    }.toList()..sort();
    return [for (final d in out) DateTime(d.year, d.month, d.day)];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gender': gender,
    'birthYear': birthYear,
    'relation': relation,
    'days': days?.map(ymd).toList(),
    'checkIn': checkIn == null ? null : ymd(checkIn!),
    'checkOut': checkOut == null ? null : ymd(checkOut!),
    'phone': phone,
    'cell': cell,
    'zone': zone,
    if (minister) 'minister': true,
    if (church != null) 'church': church,
    'extra': extra,
  };

  factory Person.fromJson(Map j) => Person(
    id: j['id'] == null ? null : '${j['id']}',
    name: '${j['name'] ?? ''}',
    gender: switch (j['gender']) {
      'F' => 'F',
      '' => '',
      _ => 'M',
    },
    birthYear: _int(j['birthYear']),
    relation: '${j['relation'] ?? '본인'}',
    days: j['days'] is List
        ? [for (final d in j['days'] as List) ?_date(d)]
        : null,
    checkIn: _date(j['checkIn']),
    checkOut: _date(j['checkOut']),
    phone: _str(j['phone']),
    cell: _str(j['cell']),
    zone: _str(j['zone']),
    minister: j['minister'] == true,
    church: _str(j['church']),
    extra: {
      if (j['extra'] is Map)
        for (final e in (j['extra'] as Map).entries) '${e.key}': '${e.value}',
    },
  );
}

class Bank {
  Bank({this.bank = '', this.account = '', this.holder = ''});
  String bank, account, holder;

  bool get isEmpty => account.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'bank': bank,
    'account': account,
    'holder': holder,
  };

  factory Bank.fromJson(Object? j) => j is Map
      ? Bank(
          bank: '${j['bank'] ?? ''}',
          account: '${j['account'] ?? ''}',
          holder: '${j['holder'] ?? ''}',
        )
      : Bank();
}

/// 집회 구분. 만들 때 정하고 나중에 바꾸지 않는다 (이미 만든 방·배정과 어긋난다).
enum GatheringKind {
  /// 신청자가 참석자가 된다. 방은 운영자가 호수로 만든다.
  gathering('집회'),

  /// 신청자가 재워 줄 가정이다. 확정하면 그 이름으로 방이 생기고,
  /// 운영자가 따로 등록한 참석자를 그 방에 배치한다.
  homestay('홈스테이');

  const GatheringKind(this.label);
  final String label;

  static GatheringKind parse(Object? s) => values.asNameMap()['$s'] ?? gathering;
}

/// 홈스테이 신청서에서 수용 인원을 받는 사용자 정의 항목 이름.
/// 전용 칸을 새로 만들지 않고 이미 있는 항목 기능을 쓴다 — 값은 `people[0].extra` 에 들어간다.
const homestayCapacityField = '수용 인원';

/// 일정표 한 줄. [time] 은 '09:00' 같은 자유 문자열 — 비우면 종일 일정.
typedef ScheduleItem = ({DateTime date, String time, String title});

/// 홈스테이 신청자(가정)에게 보여 줄, 그 집에 배정된 참석자 한 명.
/// 운영자 메모(note)는 담지 않는다 — 신청자에게 보일 내용이 아니다.
typedef AssignedGuest = ({
  String name,
  String gender,
  int age,
  String? phone,
  String? cell,
  String? zone,
});

/// 집회 설정 (서버 `gatherings` 한 행).
class Gathering {
  Gathering({
    this.id = '',
    required this.name,
    this.kind = GatheringKind.gathering,
    required this.start,
    required this.end,
    List<String>? themes,
    List<ScheduleItem>? schedule,
    this.place,
    this.address,
    this.notice,
    this.posterUrl,
    this.backgroundUrl,
    FeeRule? fee,
    Bank? bank,
    List<String>? formFields,
    List<String>? hiddenFields,
    List<String>? requiredFields,
    this.open = false,
    this.deadline,
    this.ministerNoticeOn = true,
    String? ministerNotice,
  }) : ministerNotice = ministerNotice ?? defaultMinisterNotice,
       themes = themes ?? [],
       schedule = schedule ?? [],
       fee = fee ?? FeeRule(),
       bank = bank ?? Bank(),
       formFields = formFields ?? [],
       hiddenFields = hiddenFields ?? [],
       requiredFields = requiredFields ?? [...defaultRequiredFields];

  /// 이 칸이 생기기 전 집회의 필수 항목 (서버 기본값과 같다).
  static const defaultRequiredFields = ['birthYear', 'gender'];

  /// '' = 아직 서버에 저장 안 됨.
  String id;
  String name;

  /// 집회냐 홈스테이냐. 홈스테이는 확정한 신청마다 방이 생긴다 (store.syncHomestayRooms).
  GatheringKind kind;
  bool get isHomestay => kind == GatheringKind.homestay;
  DateTime start, end;
  List<String> themes;

  /// 일정표. 기간 밖 날짜의 항목은 화면에 안 보이지만 지우지도 않는다
  /// (날짜를 잘못 바꿨다 되돌리면 그대로 살아 있게).
  List<ScheduleItem> schedule;
  String? place, address, notice, posterUrl, backgroundUrl;
  FeeRule fee;
  Bank bank;

  /// 신청서에 나오는 사용자 정의 항목. 관리자 앱의 참석자 항목과 같은 이름.
  List<String> formFields;

  /// 운영자가 신청서에서 뺀 기본 항목: 'birthYear' · 'gender' · 'cell' · 'zone' · 'minister'.
  /// 출생연도를 빼면 모두 성인 금액으로 계산한다.
  List<String> hiddenFields;

  /// 신청서에 [field] 칸이 나오는가.
  bool asks(String field) => !hiddenFields.contains(field);

  /// 운영자가 필수로 정한 기본 항목. 신청서에 나오는 칸만 뜻이 있다 ([requires]).
  /// 선택 항목을 비우면 출생연도는 성인 금액, 성별은 '' = 모름으로 들어간다.
  List<String> requiredFields;

  /// 신청서에서 [field] 칸을 꼭 채워야 하는가.
  bool requires(String field) => asks(field) && requiredFields.contains(field);
  bool open;

  /// 이 날까지 신청 받는다.
  DateTime? deadline;

  static const defaultMinisterNotice =
      '사역자의 경우 추가 할인이 있을 수 있습니다. 주최 측에 문의해 주세요.';

  /// 사역자를 체크한 신청자에게 신청 완료·조회 화면에서 보여 줄 안내.
  bool ministerNoticeOn;
  String ministerNotice;

  /// [people] 신청에 사역자 안내를 보여 주는가 — 사역자를 체크한 사람이 있을 때만.
  bool ministerNoticeFor(Iterable<Person> people) =>
      asks('minister') &&
      ministerNoticeOn &&
      ministerNotice.trim().isNotEmpty &&
      people.any((p) => p.minister);

  int get nights => _nights(_day(start), _day(end));

  /// 신청 받는 중인가. 서버(`_assert_open`)와 같은 규칙 — 마감일 당일까지.
  bool acceptingOn(DateTime now) =>
      open && (deadline == null || !_day(now).isAfter(_day(deadline!)));

  /// 집회 기간의 날짜들 (시작일 ~ 종료일).
  List<DateTime> get days =>
      [for (var i = 0; i <= nights; i++) _day(start).add(Duration(days: i))]
          .map((d) => DateTime(d.year, d.month, d.day))
          .toList();

  /// [d] 날의 일정 (시간 순). 운영자 편집 화면과 신청 웹이 같은 순서를 본다.
  List<ScheduleItem> scheduleOn(DateTime d) =>
      [
        for (final s in schedule)
          if (_day(s.date) == _day(d)) s,
      ]..sort((a, b) => a.time.compareTo(b.time));

  /// 집회 기간 안에 적어 둔 일정이 하나라도 있는가.
  bool get hasSchedule => days.any((d) => scheduleOn(d).isNotEmpty);

  Quote quoteFor(
    List<Person> people,
    DateTime appliedAt, {
    Discount discount = Discount.none,
  }) => quote(
    fee,
    start: start,
    end: end,
    people: people,
    appliedAt: appliedAt,
    discount: discount,
  );

  Gathering copy() => Gathering.fromRow({...toRow(), 'id': id});

  /// 서버에 쓰는 칸들. id 는 넣지 않는다 (insert 때 서버가 만든다).
  Map<String, dynamic> toRow() => {
    'name': name,
    'kind': kind.name,
    'themes': themes,
    'schedule': [
      for (final s in schedule)
        {'date': ymd(s.date), 'time': s.time, 'title': s.title},
    ],
    'place': place,
    'address': address,
    'notice': notice,
    'start_date': ymd(start),
    'end_date': ymd(end),
    'poster_url': posterUrl,
    'background_url': backgroundUrl,
    'fee': fee.toJson(),
    'bank': bank.toJson(),
    'form_fields': formFields,
    'hidden_fields': hiddenFields,
    'required_fields': requiredFields,
    'open': open,
    'deadline': deadline == null ? null : ymd(deadline!),
    'minister_notice_on': ministerNoticeOn,
    'minister_notice': ministerNotice,
  };

  factory Gathering.fromRow(Map r) => Gathering(
    id: '${r['id'] ?? ''}',
    name: '${r['name'] ?? ''}',
    kind: GatheringKind.parse(r['kind']),
    start: _date(r['start_date']) ?? DateTime.now(),
    end: _date(r['end_date']) ?? DateTime.now(),
    schedule: _scheduleIn(r['schedule']),
    themes: [for (final t in (r['themes'] as List? ?? [])) '$t'],
    place: _str(r['place']),
    address: _str(r['address']),
    notice: _str(r['notice']),
    posterUrl: _str(r['poster_url']),
    backgroundUrl: _str(r['background_url']),
    fee: FeeRule.fromJson(r['fee']),
    bank: Bank.fromJson(r['bank']),
    formFields: [for (final f in (r['form_fields'] as List? ?? [])) '$f'],
    hiddenFields: [for (final f in (r['hidden_fields'] as List? ?? [])) '$f'],
    requiredFields: r['required_fields'] is List
        ? [for (final f in r['required_fields'] as List) '$f']
        : null,
    open: r['open'] == true,
    deadline: _date(r['deadline']),
    ministerNoticeOn: r['minister_notice_on'] != false,
    ministerNotice: _str(r['minister_notice']),
  );
}

enum RegStatus {
  pending('입금대기'),
  confirmed('입금확인'),
  cancelled('취소');

  const RegStatus(this.label);
  final String label;

  /// 무료 집회는 입금이 없으니 '대기' / '확정'.
  String labelFor({required bool free}) => switch (this) {
    pending when free => '대기',
    confirmed when free => '확정',
    _ => label,
  };

  static RegStatus parse(Object? s) => values.asNameMap()['$s'] ?? pending;
}

/// 신청 1건 (서버 `registrations` 한 행 또는 조회 함수 결과).
class Registration {
  Registration({
    required this.id,
    required this.gatheringId,
    required this.phone,
    required this.people,
    this.depositor,
    this.memo,
    this.quoted = 0,
    this.status = RegStatus.pending,
    this.paid = 0,
    this.paidAt,
    this.adminMemo,
    this.discount = Discount.none,
    List<AssignedGuest>? assigned,
    required this.createdAt,
  }) : assigned = assigned ?? [];

  String id, gatheringId, phone;

  /// 운영자가 이 신청(가족·그룹 전체)에 준 지정 할인. 신청자는 못 바꾼다.
  Discount discount;
  List<Person> people;
  String? depositor, memo, adminMemo;

  /// 신청 웹이 보여준 금액 (참고용).
  int quoted;
  RegStatus status;
  int paid;
  DateTime? paidAt;

  /// 홈스테이에서 이 가정에 배정된 참석자. `lookup_registration` 이 같이 돌려준다.
  /// 운영자 앱이 읽는 `registrations` 행에는 없어서 그때는 항상 비어 있다.
  List<AssignedGuest> assigned;

  /// 신청 시각 (한국 시간). 사전등록 할인 기준.
  DateTime createdAt;

  String get applicant => people.isEmpty ? '' : people.first.name;
  String get depositorName =>
      (depositor ?? '').trim().isNotEmpty ? depositor!.trim() : applicant;

  factory Registration.fromRow(Map r) => Registration(
    id: '${r['id']}',
    gatheringId: '${r['gathering_id']}',
    phone: '${r['phone'] ?? ''}',
    people: [
      for (final p in (r['people'] as List? ?? []))
        if (p is Map) Person.fromJson(p),
    ],
    depositor: _str(r['depositor']),
    memo: _str(r['memo']),
    quoted: _int(r['quoted']),
    status: RegStatus.parse(r['status']),
    paid: _int(r['paid']),
    paidAt: _date(r['paid_at']),
    adminMemo: _str(r['admin_memo']),
    discount: Discount(
      pct: _int(r['discount_pct']),
      amount: _int(r['discount_amount']),
      note: _str(r['discount_note']),
    ),
    assigned: [
      for (final a in (r['assigned'] as List? ?? []))
        if (a is Map)
          (
            name: '${a['name'] ?? ''}',
            gender: '${a['gender'] ?? ''}',
            age: _int(a['age']),
            phone: _str(a['phone']),
            cell: _str(a['cell']),
            zone: _str(a['zone']),
          ),
    ],
    createdAt: (DateTime.tryParse('${r['created_at']}') ?? DateTime.now())
        .toLocal(),
  );
}

// ---------------------------------------------------------------------------
// 회비 계산
// ---------------------------------------------------------------------------

class QuoteLine {
  const QuoteLine(this.person, this.group, this.days, this.full, this.amount);
  final Person person;
  final AgeGroup group;

  /// 참석하는 날 (집회 기간 안, 정렬).
  final List<DateTime> days;
  final bool full;
  final int amount;

  /// 이 사람이 묵는 박수. 0 = 당일만.
  int get nights => nightsOf(days).length;

  /// "전체" / "1박" / "당일" / "1박 + 당일"
  String get stay {
    if (full) return '전체';
    final visits = dayVisits(days);
    return [
      if (nights > 0) '$nights박',
      if (visits > 0) visits == 1 ? '당일' : '당일 $visits일',
    ].join(' + ');
  }
}

/// 고른 날 중 다음 날도 고른 날 = 그 밤을 묵는다.
List<DateTime> nightsOf(List<DateTime> days) {
  final set = days.map(_day).toSet();
  return [
    for (final d in days)
      if (set.contains(_day(d).add(const Duration(days: 1)))) d,
  ];
}

/// 앞뒤 날을 모두 안 고른 날 = 당일로만 오는 날의 수.
int dayVisits(List<DateTime> days) {
  final set = days.map(_day).toSet();
  bool has(DateTime d, int off) => set.contains(d.add(Duration(days: off)));
  return set.where((d) => !has(d, -1) && !has(d, 1)).length;
}

/// 지정 할인. 운영자가 신청 1건에 비율([pct]%) 또는 금액([amount]원)으로 준다.
class Discount {
  const Discount({this.pct = 0, this.amount = 0, this.note});
  final int pct, amount;

  /// 사유. 신청자 조회 화면에도 보인다.
  final String? note;

  static const none = Discount();

  bool get isEmpty => pct <= 0 && amount <= 0;
}

class Quote {
  const Quote(
    this.lines,
    this.earlyPct,
    this.perRegistration, [
    this.discount = Discount.none,
  ]);
  final List<QuoteLine> lines;
  final int earlyPct;
  final int perRegistration;
  final Discount discount;

  int get subtotal => lines.fold(0, (s, l) => s + l.amount);

  /// 할인 후 금액의 원 미만을 버리도록 계산한다 (할인액 쪽이 올림).
  int get earlyDiscount => subtotal - subtotal * (100 - earlyPct) ~/ 100;

  /// 지정 할인 전 합계. 신청 웹이 저장한 금액(`quoted`)은 이것과 비교한다.
  int get beforeDiscount => subtotal - earlyDiscount + perRegistration;

  /// 지정 할인액 = 합계(그룹당 포함)의 pct% + amount. 합계보다 크게 빼지 않는다.
  int get specialDiscount {
    final b = beforeDiscount;
    return math.min(b, b - b * (100 - discount.pct) ~/ 100 + discount.amount);
  }

  int get total => beforeDiscount - specialDiscount;

  /// "성인 2 · 중고등 1 · 유치 1"
  String get summary {
    final c = <AgeGroup, int>{};
    for (final l in lines) {
      c[l.group] = (c[l.group] ?? 0) + 1;
    }
    return [
      for (final g in AgeGroup.values)
        if (c[g] != null) '${g.label} ${c[g]}',
    ].join(' · ');
  }
}

/// 신청 합계와 내역. 신청 웹·조회·관리자 화면 전부 이것 하나를 부른다.
/// [appliedAt] = 신청일 (사전등록 할인 기준).
///
/// - 모든 날에 참석하면 전체 참석(정액), 아니면 부분 참석
///   (1박당 × 이어진 날 사이 박수 + 당일 × 앞뒤 없이 혼자 고른 날 수).
/// - 일정은 집회 기간 안으로 잘라서 본다.
/// - 부분 참석 금액은 전체 참석자가 내는 금액을 넘지 않는다.
/// - 참석자가 없으면 그룹당 금액도 붙지 않는다 (빈 신청서에 금액이 뜨지 않게).
Quote quote(
  FeeRule fee, {
  required DateTime start,
  required DateTime end,
  required List<Person> people,
  required DateTime appliedAt,
  Discount discount = Discount.none,
}) {
  final s = _day(start);
  final e = _day(end).isBefore(s) ? s : _day(end);
  final allNights = _nights(s, e);
  final fullPct = fee.fullDiscountPct.clamp(0, 100);

  QuoteLine line(Person p) {
    final g = fee.groupOf(s.year - p.birthYear);
    final days = p.daysIn(s, e);

    final nightly = fee.perNight[g] ?? 0;
    final day = fee.dayOnly[g] ?? 0;
    final fullBase = fee.full[g] ?? (allNights > 0 ? nightly * allNights : day);
    final fullPrice = fullBase * (100 - fullPct) ~/ 100;

    final isFull = days.length == allNights + 1;
    final amount = isFull
        ? fullPrice
        : math.min(
            nightly * nightsOf(days).length + day * dayVisits(days),
            fullPrice,
          );
    return QuoteLine(p, g, days, isFull, amount);
  }

  final lines = people.map(line).toList();
  return Quote(
    lines,
    lines.isEmpty ? 0 : fee.earlyPctOn(appliedAt, s).clamp(0, 100),
    lines.isEmpty ? 0 : fee.perRegistration,
    lines.isEmpty
        ? Discount.none
        : Discount(
            pct: discount.pct.clamp(0, 100),
            amount: math.max(0, discount.amount),
            note: discount.note,
          ),
  );
}

// ---------------------------------------------------------------------------
// 표시 도우미 (두 앱 공용)
// ---------------------------------------------------------------------------

String ymd(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// "10-09(금)"
String mdw(DateTime d) =>
    '${_pad2(d.month)}-${_pad2(d.day)}(${_weekdays[d.weekday - 1]})';

/// [d] 의 [n]일 전 날짜.
DateTime daysBefore(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

/// "2박3일" / "당일"
String stayLabel(int nights) => nights == 0 ? '당일' : '$nights박${nights + 1}일';

/// 415000 → "415,000원"
String won(int n) =>
    '${n < 0 ? '-' : ''}${n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// "01012345678" → "010-1234-5678". 모양이 다르면 그대로.
String fmtPhone(String p) {
  final d = digitsOnly(p);
  if (d.length == 11) {
    return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  }
  return p;
}

/// 서버와 같은 규칙: 010 등 01X 로 시작하는 10~11자리.
bool validPhone(String p) => RegExp(r'^01[0-9]{8,9}$').hasMatch(digitsOnly(p));

final _rand = math.Random.secure();

String newPersonId() =>
    List.generate(16, (_) => _rand.nextInt(36).toRadixString(36)).join();

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 날짜만 남긴 UTC. 일수 계산이 서머타임 등에 흔들리지 않게 UTC 로 뺀다.
DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _nights(DateTime from, DateTime to) => to.difference(from).inDays;

Map<String, int> _groupsOut(Map<AgeGroup, int> m) => {
  for (final e in m.entries) e.key.name: e.value,
};

Map<AgeGroup, int> _groupsIn(Object? m) {
  final names = AgeGroup.values.asNameMap();
  return {
    if (m is Map)
      for (final e in m.entries) ?names['${e.key}']: _int(e.value),
  };
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

String? _str(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// 서버의 schedule jsonb → 일정 목록. 날짜가 없거나 깨진 줄은 버린다.
List<ScheduleItem> _scheduleIn(Object? j) => [
  if (j is List)
    for (final e in j)
      if (e is Map && _date(e['date']) != null)
        (
          date: _date(e['date'])!,
          time: '${e['time'] ?? ''}',
          title: '${e['title'] ?? ''}',
        ),
];

/// "2026-10-09" → 그 날 0시(현지). 없거나 깨졌으면 null.
DateTime? _date(Object? v) {
  final d = v == null ? null : DateTime.tryParse('$v');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}
