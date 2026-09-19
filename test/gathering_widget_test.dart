// 새 화면들 — 신청 웹(휴대폰 폭)과 관리자 화면. 서버는 가짜로 바꿔 끼운다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/main_public.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/screens/attendees.dart' show AttendeesScreen;
import 'package:room_assignment/screens/gathering_settings.dart';
import 'package:room_assignment/screens/gatherings.dart';
import 'package:room_assignment/screens/registrations.dart';
import 'package:room_assignment/screens/rooms.dart';
import 'package:room_assignment/theme.dart';

/// 메모리 서버. 실제 서버 함수(supabase/schema.sql)와 같은 규칙만 흉내 낸다.
class FakeRemote extends Remote {
  FakeRemote({this.admin = true});
  bool admin;
  final gs = <Gathering>[];
  final regs = <Registration>[];
  final pins = <String, String>{};
  final patches = <Map<String, dynamic>>[];
  Map<String, dynamic>? lastSubmit;

  @override
  bool get signedIn => admin;

  @override
  String? get adminEmail => admin ? 'admin@test' : null;

  @override
  Future<void> signIn(String email, String password) async {
    if (password != 'pw') throw const RemoteError('Invalid login credentials');
    admin = true;
  }

  String? newPassword;

  @override
  Future<void> changePassword(String? current, String next) async {
    if (current != null && current != 'pw') {
      throw const RemoteError('지금 비밀번호가 다릅니다.');
    }
    newPassword = next;
  }

  final requests = <AdminRequest>[];
  final approved = <String>[];

  @override
  Future<void> signUp(String name, String email, String password) async =>
      requests.add((
        id: 'u${requests.length + 1}',
        email: email,
        name: name,
        at: DateTime(2026, 9, 1),
      ));

  @override
  Future<List<AdminRequest>> adminRequests() async => [...requests];

  @override
  Future<void> approveAdmin(String userId) async {
    requests.removeWhere((r) => r.id == userId);
    approved.add(userId);
  }

  @override
  Future<void> rejectAdmin(String userId) async =>
      requests.removeWhere((r) => r.id == userId);

  @override
  Future<List<Gathering>> gatherings() async => [for (final g in gs) g.copy()];

  @override
  Future<Gathering?> gathering(String id) async =>
      gs.where((g) => g.id == id).firstOrNull?.copy();

  @override
  Future<Gathering> saveGathering(Gathering g) async {
    final s = g.copy();
    if (s.id.isEmpty) s.id = 'g${gs.length + 1}';
    gs
      ..removeWhere((x) => x.id == s.id)
      ..add(s);
    return s.copy();
  }

  @override
  Future<Map<String, ({int total, int confirmed})>>
  registrationCounts() async => {};

  @override
  Future<List<Registration>> registrations(String gatheringId) async => [
    for (final r in regs)
      if (r.gatheringId == gatheringId) r,
  ];

  @override
  Future<Registration> patchRegistration(
    String id,
    Map<String, dynamic> fields,
  ) async {
    patches.add(fields);
    final r = regs.firstWhere((r) => r.id == id);
    if (fields['status'] != null) r.status = RegStatus.parse(fields['status']);
    if (fields.containsKey('paid')) r.paid = fields['paid'] as int;
    return r;
  }

  @override
  Future<void> deleteRegistration(String id) async =>
      regs.removeWhere((r) => r.id == id);

  /// 집회 id → 방배정 문서.
  final plans = <String, Map<String, dynamic>>{};

  @override
  Future<({Map<String, dynamic> data, int version})?> roomPlan(
    String gatheringId,
  ) async {
    final p = plans[gatheringId];
    return p == null ? null : (data: p, version: 1);
  }

  @override
  Future<int> saveRoomPlan(
    String gatheringId,
    Map<String, dynamic> data,
    int version,
  ) async {
    plans[gatheringId] = data;
    return version + 1;
  }

  @override
  Future<String> submit(
    String gatheringId, {
    required String phone,
    required String pin,
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async {
    lastSubmit = {
      'phone': digitsOnly(phone),
      'pin': pin,
      'people': people,
      'quoted': quoted,
      'depositor': depositor,
    };
    final r = Registration(
      id: 'r${regs.length + 1}',
      gatheringId: gatheringId,
      phone: digitsOnly(phone),
      people: people,
      depositor: depositor,
      quoted: quoted,
      createdAt: DateTime.now(),
    );
    regs.add(r);
    pins[r.id] = pin;
    return r.id;
  }

  @override
  Future<String> adminSubmit(
    String gatheringId, {
    required String phone,
    required String pin,
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async {
    final id = await submit(
      gatheringId,
      phone: phone,
      pin: pin,
      people: people,
      depositor: depositor,
      memo: memo,
      quoted: quoted,
    );
    lastSubmit!['admin'] = true;
    return id;
  }

  @override
  Future<Registration?> lookup(
    String gatheringId,
    String phone,
    String pin,
  ) async => regs
      .where(
        (r) =>
            r.gatheringId == gatheringId &&
            r.phone == digitsOnly(phone) &&
            pins[r.id] == pin,
      )
      .firstOrNull;

  @override
  Future<Registration?> cancelMine(
    String gatheringId,
    String phone,
    String pin,
  ) async {
    final r = await lookup(gatheringId, phone, pin);
    if (r != null && r.status != RegStatus.pending) {
      throw const RemoteError('NOT_EDITABLE');
    }
    r?.status = RegStatus.cancelled;
    return r;
  }
}

Gathering sample() => Gathering(
  id: 'g1',
  name: '신촌하나교회 가족수양회',
  start: DateTime(2026, 10, 9),
  end: DateTime(2026, 10, 11),
  themes: ['영혼육', '다음세대'],
  place: '수양관',
  address: '경기도 가평군',
  open: true,
  bank: Bank(bank: '국민', account: '000-00-0000', holder: '신촌하나교회'),
  fee: FeeRule(
    full: {
      AgeGroup.adult: 150000,
      AgeGroup.youth: 120000,
      AgeGroup.child: 100000,
      AgeGroup.kinder: 60000,
      AgeGroup.infant: 0,
    },
    perNight: {AgeGroup.adult: 70000, AgeGroup.youth: 60000},
    dayOnly: {AgeGroup.adult: 30000},
    perRegistration: 10000,
  ),
);

Gathering homestay() => Gathering(
  id: 'h1',
  name: '겨울 홈스테이',
  kind: GatheringKind.homestay,
  start: DateTime(2026, 10, 9),
  end: DateTime(2026, 10, 11),
  open: true,
  formFields: [homestayCapacityField],
);

/// 홈스테이 신청 한 건 (가정).
Registration homeReg({
  RegStatus status = RegStatus.confirmed,
  String capacity = '3',
  List<AssignedGuest> assigned = const [],
}) => Registration(
  id: 'h-r1',
  gatheringId: 'h1',
  phone: '01012345678',
  people: [
    Person(
      id: 'h1',
      name: '김호스트',
      gender: 'M',
      birthYear: 1980,
      extra: {homestayCapacityField: capacity},
    ),
  ],
  status: status,
  createdAt: DateTime(2026, 9, 10),
  assigned: assigned,
);

Registration pendingReg({int? quoted}) => Registration(
  id: 'r1',
  gatheringId: 'g1',
  phone: '01012345678',
  people: [
    Person(id: 'a', name: '홍길동', gender: 'M', birthYear: 1985),
    Person(id: 'b', name: '홍딸', gender: 'F', birthYear: 2012, relation: '자녀'),
  ],
  quoted: quoted ?? 280000,
  createdAt: DateTime(2026, 9, 10),
);

late FakeRemote fake;

void setView(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: page));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  setUp(() {
    fake = FakeRemote()..gs.add(sample());
    remote = fake;
    current.value = null;
    passwordRecovery.value = false;
    store.event = Event(
      name: 'x',
      startDate: DateTime(2026, 10, 9),
      endDate: DateTime(2026, 10, 11),
    );
  });

  group('신청 웹 (휴대폰 폭 400px)', () {
    testWidgets('집회 페이지: 이름·주제·회비·계좌·버튼', (tester) async {
      setView(tester, const Size(400, 1400));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('신촌하나교회 가족수양회'), findsOneWidget);
      expect(find.text('#영혼육'), findsOneWidget);
      expect(find.text('150,000원'), findsOneWidget);
      expect(find.text('국민 000-00-0000'), findsOneWidget);
      expect(find.text('지도 보기'), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '신청하기'),
      );
      expect(apply.onPressed, isNotNull);
    });

    testWidgets('출생연도를 안 받으면 회비표는 성인 줄만', (tester) async {
      fake.gs.first.hiddenFields = ['birthYear'];
      setView(tester, const Size(400, 1400));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(find.text('성인'), findsOneWidget);
      expect(find.text('중고등'), findsNothing);
      expect(find.textContaining('출생연도로 계산'), findsNothing);
    });

    testWidgets('신청을 받지 않으면 [신청하기]가 꺼진다', (tester) async {
      fake.gs.first.open = false;
      setView(tester, const Size(400, 1400));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(find.text('지금은 신청을 받지 않습니다.'), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '신청하기'),
      );
      expect(apply.onPressed, isNull);
    });

    testWidgets('링크가 잘못되면 안내', (tester) async {
      setView(tester, const Size(400, 800));
      await tester.pumpWidget(const PublicApp(gatheringId: 'nope'));
      await tester.pumpAndSettle();
      expect(find.textContaining('집회를 찾지 못했습니다'), findsOneWidget);
      // 키를 바꿔 새 앱으로 띄운다 (같은 자리면 이전 화면 상태가 남는다).
      await tester.pumpWidget(const PublicApp(key: ValueKey('no-id')));
      await tester.pumpAndSettle();
      expect(find.textContaining('잘못된 링크'), findsOneWidget);
    });

    testWidgets('빈 신청서를 내면 막고 빨간 표시', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('빨간 표시된 칸을 확인하세요.'), findsOneWidget);
      expect(find.text('성별을 고르세요'), findsOneWidget);
      expect(find.text('동의가 필요합니다.'), findsOneWidget);
      expect(fake.lastSubmit, isNull);
    });

    testWidgets('가족 신청: 금액이 바로 계산되고 그 금액으로 접수된다', (tester) async {
      setView(tester, const Size(400, 3200));
      await pumpPage(tester, ApplyPage(gathering: sample()));

      await tester.enterText(field('이름 *'), '홍길동');
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.tap(find.text('남').first);
      await tester.pumpAndSettle();
      expect(find.text('160,000원'), findsOneWidget); // 150,000 + 가족당 10,000
      await tester.enterText(field('셀'), '1셀');
      await tester.enterText(field('존'), 'A존');

      await tester.tap(find.text('동반 참석자 추가 (가족 등)'));
      await tester.pumpAndSettle();
      await tester.enterText(field('이름 *').at(1), '홍딸');
      await tester.enterText(field('출생연도 *').at(1), '2012'); // 14세 = 중고등
      await tester.tap(find.text('여').at(1));
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.pumpAndSettle();
      expect(find.text('280,000원'), findsOneWidget);
      expect(find.text('성인 1 · 중고등 1'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(find.text('이대로 신청할까요?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('신청이 접수되었습니다'), findsOneWidget);
      expect(find.text('입금자명: 홍길동'), findsOneWidget);
      final s = fake.lastSubmit!;
      expect(s['quoted'], 280000);
      expect(s['phone'], '01012345678');
      expect(s['pin'], '1234');
      final people = s['people'] as List<Person>;
      expect(people.map((p) => (p.name, p.gender, p.birthYear)), [
        ('홍길동', 'M', 1985),
        ('홍딸', 'F', 2012),
      ]);
      expect(people.first.phone, '01012345678');
      expect(people.last.relation, '자녀');
      // 셀·존은 신청자 것을 따라가지 않고 빈칸으로 시작한다.
      expect((people.first.cell, people.first.zone), ('1셀', 'A존'));
      expect((people.last.cell, people.last.zone), (null, null));
    });

    testWidgets('운영자가 정한 필수 여부: 출생연도·성별 선택, 셀 필수', (tester) async {
      setView(tester, const Size(400, 2400));
      final g = sample()..requiredFields = ['cell'];
      await pumpPage(tester, ApplyPage(gathering: g));
      await tester.enterText(field('이름 *'), '홍길동');
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      // 셀만 막는다. 출생연도·성별은 비워도 된다.
      expect(find.text('셀을 입력하세요'), findsOneWidget);
      expect(find.text('성별을 고르세요'), findsNothing);
      expect(find.text('4자리 연도로 입력하세요'), findsNothing);

      await tester.enterText(field('셀 *'), '1셀');
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      final p = (fake.lastSubmit!['people'] as List<Person>).single;
      expect((p.gender, p.birthYear, p.cell), ('', 0, '1셀')); // 0 = 성인 금액
      expect(Gathering.fromRow({...g.toRow(), 'id': g.id}).requiredFields, [
        'cell',
      ]);
      expect(Gathering.fromRow({}).requiredFields, ['birthYear', 'gender']);
    });

    testWidgets('사역자를 체크하면 교회 이름이 필수이고, 완료 화면에 안내가 나온다', (tester) async {
      setView(tester, const Size(400, 2400));
      final g = sample()..requiredFields = [];
      await pumpPage(tester, ApplyPage(gathering: g));
      await tester.enterText(field('이름 *'), '김목사');
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      expect(field('교회 이름 *'), findsNothing);
      await tester.tap(find.text('사역자입니다'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(find.text('교회 이름을 입력하세요'), findsOneWidget);
      expect(fake.lastSubmit, isNull);

      await tester.enterText(field('교회 이름 *'), '신촌하나교회');
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      final p = (fake.lastSubmit!['people'] as List<Person>).single;
      expect((p.minister, p.church), (true, '신촌하나교회'));
      expect(find.text(Gathering.defaultMinisterNotice), findsOneWidget);
    });

    testWidgets('운영자가 끈 출생연도·셀·존은 신청서에 없고, 금액은 성인으로', (tester) async {
      setView(tester, const Size(400, 2400));
      final g = sample()
        ..hiddenFields = ['birthYear', 'gender', 'cell', 'zone'];
      await pumpPage(tester, ApplyPage(gathering: g));
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(Person.fromJson({'gender': ''}).gender, ''); // 모름은 남자로 바뀌지 않는다
      for (final label in ['출생연도 *', '셀', '존']) {
        expect(find.widgetWithText(TextFormField, label), findsNothing);
      }
      expect(find.textContaining('성인 · 전체'), findsOneWidget);
      expect(
        Gathering.fromRow({...g.toRow(), 'id': g.id}).hiddenFields,
        g.hiddenFields,
      );
    });

    testWidgets('부분 참석으로 바꾸면 1박 금액이 된다', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.tap(find.widgetWithText(SwitchListTile, '전체 참석'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 금·토 체크 = 1박 70,000 + 가족당 10,000
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-09(금)'));
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-10(토)'));
      await tester.pumpAndSettle();
      expect(find.text('80,000원'), findsOneWidget);
      expect(find.textContaining('성인 · 1박'), findsOneWidget);
    });

    testWidgets('일정표를 적어 두면 집회 페이지에 날짜별로 보인다', (tester) async {
      fake.gs
        ..clear()
        ..add(
          sample()
            ..schedule = [
              (date: DateTime(2026, 10, 9), time: '19:30', title: '개회예배'),
              (date: DateTime(2026, 10, 9), time: '21:00', title: '조모임'),
              (date: DateTime(2027, 1, 1), time: '', title: '기간 밖 일정'),
            ],
        );
      setView(tester, const Size(400, 2000));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('일정'), findsOneWidget);
      expect(find.text('10-09(금)'), findsOneWidget);
      expect(find.text('19:30'), findsOneWidget);
      expect(find.text('개회예배'), findsOneWidget);
      expect(find.text('조모임'), findsOneWidget);
      expect(find.text('기간 밖 일정'), findsNothing); // 기간 밖은 안 보인다
    });

    testWidgets('일정이 없으면 일정 칸 자체가 없다', (tester) async {
      setView(tester, const Size(400, 1400));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(find.text('일정'), findsNothing);
    });

    testWidgets('홈스테이 조회: 배정된 참석자가 보이고, 배정 전이면 안내', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      fake.regs.add(homeReg());
      fake.pins['h-r1'] = '1234';
      setView(tester, const Size(400, 1600));
      await pumpPage(tester, LookupPage(gathering: homestay()));
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01012345678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('우리 집에 배정된 참석자'), findsOneWidget);
      expect(find.textContaining('아직 배정 전입니다'), findsOneWidget);

      // 운영자가 배정한 뒤 다시 조회하면 명단이 뜬다
      fake.regs.single.assigned = [
        (
          name: '손님1',
          gender: 'F',
          age: 20,
          phone: '01000001111',
          cell: '믿음셀',
          zone: null,
        ),
      ];
      await tester.tap(find.widgetWithText(TextButton, '다른 번호로 조회'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(find.text('1명'), findsOneWidget);
      expect(find.text('손님1'), findsOneWidget);
      expect(find.text('여 · 20세 · 믿음셀'), findsOneWidget);
      expect(find.text('010-0000-1111'), findsOneWidget);
    });

    testWidgets('조회: 휴대폰+PIN → 상태, 입금대기면 취소', (tester) async {
      fake.regs.add(pendingReg());
      fake.pins['r1'] = '1234';
      setView(tester, const Size(400, 1600));
      await pumpPage(tester, LookupPage(gathering: sample()));

      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01012345678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '0000',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(find.textContaining('맞지 않습니다'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('입금대기'), findsOneWidget);
      expect(find.text('280,000원'), findsOneWidget);
      expect(find.text('입금자명: 홍길동'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '신청 취소'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청 취소'));
      await tester.pumpAndSettle();
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('취소된 신청입니다.'), findsOneWidget);
      expect(find.text('신청 내용 수정'), findsNothing);
    });

    testWidgets('조회: 부분 참석은 날짜가, 전체 참석은 전참 표시가 나온다', (tester) async {
      // 회비가 없는 집회 — 금액표가 없어서 참석 일정 칸에서만 날짜를 볼 수 있다.
      final free = sample()..fee = FeeRule();
      fake.gs
        ..clear()
        ..add(free);
      fake.regs.add(
        Registration(
          id: 'r1',
          gatheringId: 'g1',
          phone: '01012345678',
          people: [
            Person(id: 'a', name: '홍길동', gender: 'M', birthYear: 1985),
            Person(
              id: 'b',
              name: '홍딸',
              gender: 'F',
              birthYear: 2012,
              days: [DateTime(2026, 10, 10), DateTime(2026, 10, 11)],
            ),
          ],
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      fake.pins['r1'] = '1234';
      setView(tester, const Size(400, 1600));
      await pumpPage(tester, LookupPage(gathering: free));
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01012345678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('참석 일정'), findsOneWidget);
      // 전체 참석자는 날짜를 늘어놓지 않고 기간 한 줄
      expect(find.text('전체 참석'), findsOneWidget);
      expect(find.text('10-09(금) ~ 10-11(일) · 3일'), findsOneWidget);
      // 부분 참석자는 고른 날짜가 그대로
      expect(find.text('10-10(토)'), findsOneWidget);
      expect(find.text('10-11(일)'), findsOneWidget);
      expect(find.text('10-09(금)'), findsNothing); // 안 고른 날
      expect(find.text('1박'), findsOneWidget);
    });

    testWidgets('조회: 확정된 신청은 수정·취소 버튼이 없다', (tester) async {
      fake.regs.add(
        pendingReg()
          ..status = RegStatus.confirmed
          ..paid = 280000,
      );
      fake.pins['r1'] = '1234';
      setView(tester, const Size(400, 1600));
      await pumpPage(tester, LookupPage(gathering: sample()));
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '010-1234-5678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();
      expect(find.text('입금확인'), findsOneWidget);
      expect(find.text('확인된 입금액 280,000원'), findsOneWidget);
      expect(find.text('신청 내용 수정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '신청 취소'), findsNothing);
    });

    testWidgets('조회 → 수정: 사람을 추가하면 금액이 바뀐 채 저장된다', (tester) async {
      // 수정은 서버 함수(update_registration)로 간다. 가짜 서버에서 받은 값을 확인한다.
      final updates = <List<Person>>[];
      remote = _EditRemote(fake, updates);
      fake.regs.add(pendingReg());
      fake.pins['r1'] = '1234';
      setView(tester, const Size(400, 3200));
      await pumpPage(tester, LookupPage(gathering: sample()));
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01012345678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '조회'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('신청 내용 수정'));
      await tester.pumpAndSettle();
      expect(find.text('신청 수정'), findsOneWidget);
      expect(find.text('280,000원'), findsOneWidget);
      await tester.tap(find.text('동반 참석자 추가 (가족 등)'));
      await tester.pumpAndSettle();
      await tester.enterText(field('이름 *').at(2), '홍막내');
      await tester.enterText(field('출생연도 *').at(2), '2024'); // 영유아 0원
      await tester.tap(find.text('남').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '수정 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '수정'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(updates.single.map((p) => p.name), ['홍길동', '홍딸', '홍막내']);
      // 사람 id 는 그대로 — 관리자 앱이 이 id 로 참석자를 맞춘다
      expect(updates.single.take(2).map((p) => p.id), ['a', 'b']);
      // 조회 화면의 금액표("홍막내  영유아 · 전체")와 참석 일정에 각각 한 줄씩
      expect(find.textContaining('홍막내'), findsNWidgets(2));
      expect(find.text('참석 일정'), findsOneWidget);
      expect(find.text('전체 참석'), findsNWidgets(3));
    });
  });

  group('관리자 화면', () {
    testWidgets('첫 화면: 로그인 전엔 로그인, 틀리면 칸 옆에 안내, 맞으면 집회 목록', (tester) async {
      fake.admin = false;
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Gate());
      expect(find.text('신촌하나교회 가족수양회'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, '이메일'), 'a@test');
      await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'x');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();
      expect(find.text('이메일 또는 비밀번호가 다릅니다.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('신촌하나교회 가족수양회'), findsOneWidget);
    });

    testWidgets('재설정 메일 링크로 오면 새 비밀번호부터, 두 칸이 다르면 막는다', (tester) async {
      passwordRecovery.value = true;
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Gate());
      expect(find.text('신촌하나교회 가족수양회'), findsNothing);
      expect(find.widgetWithText(TextField, '지금 비밀번호'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, '새 비밀번호'), 'new1');
      await tester.enterText(
        find.widgetWithText(TextField, '새 비밀번호 확인'),
        'new2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '비밀번호 바꾸기'));
      await tester.pumpAndSettle();
      expect(find.text('새 비밀번호를 똑같이 두 번 입력하세요.'), findsOneWidget);
      expect(fake.newPassword, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, '새 비밀번호 확인'),
        'new1',
      );
      await tester.tap(find.widgetWithText(FilledButton, '비밀번호 바꾸기'));
      await tester.pumpAndSettle();
      expect(fake.newPassword, 'new1');
      expect(find.text('신촌하나교회 가족수양회'), findsOneWidget);
    });

    testWidgets('비밀번호 변경: 지금 비밀번호가 틀리면 막고, 맞으면 바뀐다', (tester) async {
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('admin@test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '지금 비밀번호'), 'x');
      await tester.enterText(find.widgetWithText(TextField, '새 비밀번호'), 'new1');
      await tester.enterText(
        find.widgetWithText(TextField, '새 비밀번호 확인'),
        'new1',
      );
      await tester.tap(find.widgetWithText(FilledButton, '비밀번호 바꾸기'));
      await tester.pumpAndSettle();
      expect(find.text('지금 비밀번호가 다릅니다.'), findsOneWidget);
      expect(fake.newPassword, isNull);

      await tester.enterText(find.widgetWithText(TextField, '지금 비밀번호'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, '비밀번호 바꾸기'));
      await tester.pumpAndSettle();
      expect(fake.newPassword, 'new1');
      expect(find.text('비밀번호를 바꿨습니다.'), findsOneWidget);
    });

    testWidgets('가입 신청: 칸이 비면 막고, 보내면 승인 대기 안내', (tester) async {
      fake.admin = false;
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Gate());
      await tester.tap(find.text('운영자 가입 신청'));
      await tester.pumpAndSettle();

      Finder box(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, label),
      );
      await tester.tap(find.widgetWithText(FilledButton, '가입 신청'));
      await tester.pumpAndSettle();
      expect(find.text('이름을 입력하세요.'), findsOneWidget);
      expect(fake.requests, isEmpty);

      await tester.enterText(box('이름'), '홍길동');
      await tester.enterText(box('이메일'), 'new@test');
      await tester.enterText(box('비밀번호'), 'pw1234');
      await tester.enterText(box('비밀번호 확인'), 'pw1234');
      await tester.tap(find.widgetWithText(FilledButton, '가입 신청'));
      await tester.pumpAndSettle();
      expect(fake.requests.single.email, 'new@test');
      expect(find.textContaining('기존 운영자가 승인하면'), findsOneWidget);
    });

    testWidgets('운영자 승인: 승인하면 목록에서 빠지고, 거절은 한 번 더 묻는다', (tester) async {
      fake
        ..requests.add((
          id: 'u1',
          email: 'a@x',
          name: '김철수',
          at: DateTime(2026, 9, 1),
        ))
        ..requests.add((
          id: 'u2',
          email: 'b@x',
          name: '',
          at: DateTime(2026, 9, 2),
        ));
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('admin@test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('운영자 승인'));
      await tester.pumpAndSettle();
      expect(find.text('김철수'), findsOneWidget);
      expect(find.text('b@x'), findsOneWidget); // 이름이 없으면 이메일

      await tester.tap(find.widgetWithText(FilledButton, '승인').first);
      await tester.pumpAndSettle();
      expect(fake.approved, ['u1']);
      expect(find.text('김철수'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '거절'));
      await tester.pumpAndSettle();
      expect(fake.requests, hasLength(1)); // 아직 확인 전
      await tester.tap(find.widgetWithText(FilledButton, '거절'));
      await tester.pumpAndSettle();
      expect(fake.requests, isEmpty);
      expect(find.text('승인을 기다리는 가입 신청이 없습니다.'), findsOneWidget);
    });

    testWidgets('집회 목록: 서버 집회가 카드로 보인다', (tester) async {
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('신촌하나교회 가족수양회'), findsOneWidget);
      expect(find.text('신청 받는 중'), findsOneWidget);
      expect(find.text('admin@test'), findsOneWidget);
    });

    testWidgets('새 집회: 과거 집회에서 설정·방·참석자를 골라 복사한다', (tester) async {
      fake.plans['g1'] = Event(
        name: 'x',
        startDate: DateTime(2026, 10, 9),
        endDate: DateTime(2026, 10, 11),
        rooms: [Room(id: 'r1', roomNo: '301', capacity: 4)],
        attendees: [
          Attendee(
            id: 'a',
            name: '홍길동',
            gender: 'M',
            age: 40,
            roomId: 'r1',
            checkIn: DateTime(2026, 10, 9),
            checkOut: DateTime(2026, 10, 11),
          ),
        ],
      ).toJson();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('새 집회'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Gathering?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('신촌하나교회 가족수양회 (').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('참석자 (방 배정은 풀고 새로 시작)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('만들기'));
      await tester.pumpAndSettle();

      final g2 = fake.gs.firstWhere((g) => g.id != 'g1');
      expect(g2.name, '신촌하나교회 가족수양회'); // 이름이 비어 있으면 원본 이름
      expect(g2.bank.account, '000-00-0000'); // 설정 복사
      expect((g2.open, g2.posterUrl), (false, null));
      final e = Event.fromJson(fake.plans[g2.id]!);
      expect(e.rooms.single.roomNo, '301');
      expect(e.attendees.single.roomId, isNull);
    });

    testWidgets('새 집회: 홈스테이를 고르면 수용 인원 항목이 붙는다', (tester) async {
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('새 집회'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('홈스테이'));
      await tester.pumpAndSettle();
      expect(find.textContaining('신청자가 재워 줄 가정입니다'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '집회 이름 *'),
        '겨울 홈스테이',
      );
      await tester.tap(find.text('만들기'));
      await tester.pumpAndSettle();

      final g2 = fake.gs.firstWhere((g) => g.id != 'g1');
      expect(g2.kind, GatheringKind.homestay);
      expect(g2.formFields, [homestayCapacityField]);
    });

    testWidgets('신청·입금: 홈스테이는 확정하면 그 이름으로 가정이 생긴다', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      fake.regs.add(homeReg(status: RegStatus.pending));
      current.value = homestay();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      await tester.tap(find.text('김호스트').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '입금 확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '확정'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(store.event.attendees, isEmpty); // 신청자는 참석자가 아니라 방 주인
      final room = store.event.rooms.single;
      expect((room.roomNo, room.capacity), ('김호스트', 3));
      expect(room.registrationId, 'h-r1');
      expect(find.textContaining('가정 1곳을 방으로 만들었습니다'), findsOneWidget);
    });

    testWidgets('가정 관리: 확정된 신청을 가정으로 가져온다', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      fake.regs.add(homeReg());
      current.value = homestay();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RoomsScreen()));
      expect(find.text('가정 관리'), findsOneWidget);
      expect(find.textContaining('가정이 없습니다'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '신청에서 가져오기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.event.rooms.single.roomNo, '김호스트');
      expect(find.textContaining('추가 1'), findsOneWidget);

      // 이름으로 직접 추가도 된다 (호수 범위 파서를 타지 않는다)
      await tester.tap(find.widgetWithText(FilledButton, '가정 직접 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '가정 이름'),
        '박호스트',
      );
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(store.event.rooms.map((r) => r.roomNo), ['김호스트', '박호스트']);
      expect(store.event.rooms.last.registrationId, isNull);
    });

    testWidgets('참석자: 홈스테이는 통계 대신 가정·기간 그래프가 나온다', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      current.value = homestay();
      store.event
        ..startDate = DateTime(2026, 10, 9)
        ..endDate = DateTime(2026, 10, 12)
        ..rooms.add(
          Room(id: 'h1', roomNo: '김호스트', capacity: 3, registrationId: 'h-r1'),
        )
        ..attendees.addAll([
          Attendee(
            id: 'k1',
            name: '아이하나',
            gender: 'F',
            age: 12,
            roomId: 'h1',
            checkIn: DateTime(2026, 10, 9),
            checkOut: DateTime(2026, 10, 12),
          ),
          Attendee(
            id: 'k2',
            name: '아이둘',
            gender: 'M',
            age: 10,
            checkIn: DateTime(2026, 10, 10),
            checkOut: DateTime(2026, 10, 11),
          ),
        ]);
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: AttendeesScreen()));
      expect(tester.takeException(), isNull);

      // 날짜가 맨 위 컬럼 (묵는 밤 = 9·10·11일)
      expect(find.text('9'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      // 아이마다 배정된 집이 막대에 적힌다
      expect(find.text('아이하나  여 12세'), findsOneWidget);
      expect(find.text('김호스트'), findsOneWidget);
      expect(find.text('미배정'), findsOneWidget); // 아직 집이 없는 아이
      // 홈스테이에서는 위쪽 통계·날짜 칩을 감춘다
      expect(find.textContaining('합계 '), findsNothing);
      expect(find.textContaining('전참 '), findsNothing);
      expect(find.text('존'), findsNothing);
      expect(find.text('2 / 2명'), findsOneWidget);
    });

    testWidgets('참석자: 기간을 나눈 아이는 한 줄에 두 집으로 보인다', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      current.value = homestay();
      store.event
        ..startDate = DateTime(2026, 10, 9)
        ..endDate = DateTime(2026, 10, 12)
        ..rooms.addAll([
          Room(id: 'A', roomNo: '김호스트', capacity: 4),
          Room(id: 'B', roomNo: '박호스트', capacity: 4),
        ])
        ..attendees.add(
          Attendee(
            id: 'k1',
            name: '아이하나',
            gender: 'F',
            age: 12,
            roomId: 'A',
            checkIn: DateTime(2026, 10, 9),
            checkOut: DateTime(2026, 10, 12),
          ),
        );
      // 10-11 밤부터는 다른 집으로
      final later = store.splitStay(store.event.attendees.first, DateTime(2026, 10, 11))!;
      later.roomId = 'B';

      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: AttendeesScreen()));
      expect(tester.takeException(), isNull);

      // 한 사람이므로 이름 줄은 하나 (조각 수 ·2 가 붙는다)
      expect(find.textContaining('아이하나  여 12세  ·2'), findsOneWidget);
      expect(find.text('1 / 1명'), findsOneWidget);
      // 막대는 집마다 하나씩
      expect(find.text('김호스트'), findsOneWidget);
      expect(find.text('박호스트'), findsOneWidget);
    });

    testWidgets('집회 설정: 일정표를 적어 저장하면 서버로 간다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3000));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('일정표'), findsOneWidget);
      expect(find.text('10-09(금)'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '줄 추가').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '19:30'), '19:30');
      await tester.enterText(find.widgetWithText(TextField, '개회예배'), '개회예배');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final saved = fake.gs.single.schedule.single;
      expect(
        (saved.date, saved.time, saved.title),
        (DateTime(2026, 10, 9), '19:30', '개회예배'),
      );
    });

    testWidgets('신청·입금: 로그인 전엔 로그인 안내', (tester) async {
      fake.admin = false;
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      expect(find.widgetWithText(FilledButton, '운영자 로그인'), findsOneWidget);
    });

    testWidgets('신청·입금: 입금 확인하면 확정되고 계산 금액이 입금액으로 들어간다', (tester) async {
      fake.regs.add(pendingReg());
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('홍길동'), findsNWidgets(2)); // 신청자 + 입금자명 칸
      expect(find.text('입금대기 1'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsNothing); // 금액 일치

      await tester.tap(find.text('홍길동').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '입금 확인'));
      await tester.pumpAndSettle();
      expect(find.text('계산 금액 280,000원'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '확정'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(fake.patches.single['status'], 'confirmed');
      expect(fake.patches.single['paid'], 280000);
      expect(find.text('입금확인 1'), findsOneWidget);
      // 확정한 신청의 사람은 참석자로 바로 올라간다
      expect(store.event.attendees.map((a) => a.name), ['홍길동', '홍딸']);
      expect(find.textContaining('참석자 2명을 등록했습니다'), findsOneWidget);
    });

    testWidgets('신청·입금: 운영자가 대신 받은 신청은 입금대기로 들어가고 바로 입금 확인한다', (tester) async {
      current.value = sample()..open = false; // 신청을 닫은 뒤에도 현장 접수는 된다
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      await tester.tap(find.text('신청 추가'));
      await tester.pumpAndSettle();
      expect(find.text('신청 추가 (운영자 접수)'), findsOneWidget);
      expect(find.textContaining('개인정보'), findsNothing);

      await tester.enterText(field('이름 *'), '김현장');
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.tap(find.text('남').first);
      await tester.enterText(field('휴대폰번호 *'), '010-5555-4444');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final s = fake.lastSubmit!;
      expect(s['admin'], isTrue);
      expect(s['pin'], matches(RegExp(r'^\d{4}$'))); // 미리 채운 PIN
      expect(s['quoted'], 160000);
      expect(find.text('입금대기 1'), findsOneWidget);

      // 추가한 신청이 열려 있어 바로 입금 확인 → 참석자로 올라간다
      await tester.tap(find.widgetWithText(FilledButton, '입금 확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '확정'));
      await tester.pumpAndSettle();
      expect(fake.patches.single['paid'], 160000);
      expect(store.event.attendees.map((a) => a.name), ['김현장']);
    });

    testWidgets('신청·입금: 엑셀 붙여넣기로 신청 여러 건을 넣는다 (같은 전화 = 한 신청)', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      await tester.tap(find.text('붙여넣기 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '이름\t성별\t나이\t전화\n'
        '김아빠\t남\t1985\t010-1111-2222\n' // 나이 칸에 출생연도
        '김아들\t남\t10\t01011112222\n'
        '이혼자\t여\t30\t010-3333-4444\n'
        '번호없음\t여\t30\n',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('정상 3행 · 오류 1행'), findsOneWidget);
      await tester.tap(find.text('3명 저장'));
      await tester.pumpAndSettle();

      expect(fake.regs, hasLength(2));
      final family = fake.regs.firstWhere((r) => r.phone == '01011112222');
      expect(family.people.map((p) => p.name), ['김아빠', '김아들']);
      expect(family.people.first.birthYear, 1985);
      expect(family.quoted, 150000 + 100000 + 10000); // 성인 + 초등 + 그룹당
      expect(find.text('입금대기 2'), findsOneWidget);
    });

    testWidgets('신청·입금: 취소하면 그 신청의 참석자가 빠진다 (방 배정된 사람은 미리 경고)', (tester) async {
      fake.regs.add(
        pendingReg()
          ..status = RegStatus.confirmed
          ..paid = 280000,
      );
      current.value = sample();
      Attendee att(String id, String name, {String? reg, String? room}) =>
          Attendee(
            id: id,
            name: name,
            gender: 'M',
            age: 30,
            roomId: room,
            registrationId: reg,
            checkIn: DateTime(2026, 10, 9),
            checkOut: DateTime(2026, 10, 11),
          );
      store.event.attendees.addAll([
        att('a', '홍길동', reg: 'r1', room: 'r301'),
        att('b', '홍딸', reg: 'r1'),
        att('p', '현장등록'), // 붙여넣기로 넣은 사람
      ]);
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));

      await tester.tap(find.text('홍길동').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '신청 취소'));
      await tester.pumpAndSettle();
      expect(find.textContaining('방이 배정된 1명(홍길동)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '신청 취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(fake.regs.single.status, RegStatus.cancelled);
      expect(store.event.attendees.map((a) => a.name), ['현장등록']);
      expect(find.textContaining('참석자 2명을 뺐습니다'), findsOneWidget);
    });

    testWidgets('신청·입금: 좁은 창에서 신청을 골라 상세가 열려도 표가 깨지지 않는다', (tester) async {
      fake.regs.add(pendingReg());
      current.value = sample();
      setView(tester, const Size(900, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      await tester.tap(find.text('홍길동').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('참석자: 날짜를 고르면 당일 신청자도 그날 인원에 든다 (식수)', (tester) async {
      fake.regs.add(
        Registration(
          id: 'r9',
          gatheringId: 'g1',
          phone: '01011112222',
          people: [
            Person(
              id: 'd',
              name: '당일이',
              gender: 'F',
              birthYear: 1990,
              days: [DateTime(2026, 10, 10)],
            ),
            Person(id: 'f', name: '전참이', gender: 'M', birthYear: 1980),
          ],
          quoted: 0,
          createdAt: DateTime(2026, 9, 10),
        )..status = RegStatus.confirmed,
      );
      current.value = sample();
      store.syncRegistrations(sample(), fake.regs);
      expect(store.event.attendees.map((a) => a.name), ['전참이']); // 방은 1박 이상만
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const AttendeesScreen());

      // 합계 = 기간 중 하루라도 오는 사람(당일 포함), 전참 = 모든 날 오는 사람만
      expect(find.text('합계 2명'), findsOneWidget);
      expect(find.text('전참 1명'), findsOneWidget);
      expect(find.text('10-09(금) 1명'), findsOneWidget);
      expect(find.text('10-11(일) 1명'), findsOneWidget); // 전참은 마지막 날도
      await tester.tap(find.text('10-10(토) 2명'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('당일이'), findsOneWidget);
      expect(find.text('당일'), findsOneWidget);
    });

    testWidgets('신청·입금: 신청 때 금액과 다르면 경고, 일괄 확정', (tester) async {
      fake.regs
        ..add(pendingReg(quoted: 1000)) // 조작됐거나 회비가 바뀐 경우
        ..add(
          Registration(
            id: 'r2',
            gatheringId: 'g1',
            phone: '01099998888',
            people: [
              Person(id: 'c', name: '김철수', gender: 'M', birthYear: 1990),
            ],
            quoted: 160000,
            createdAt: DateTime(2026, 9, 11),
          ),
        );
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);

      for (final box in find.byType(Checkbox).evaluate().toList()) {
        await tester.tap(find.byWidget(box.widget));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 2건 입금 확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '확정'));
      await tester.pumpAndSettle();
      expect(fake.regs.every((r) => r.status == RegStatus.confirmed), isTrue);
      // 입금액은 신청 때 값이 아니라 지금 계산한 금액
      expect(fake.regs.map((r) => r.paid), [280000, 160000]);
      expect(store.event.attendees, hasLength(3)); // 두 신청의 3명 모두 참석자로
    });

    testWidgets('신청·입금: 사역자 신청은 표시되고, 필터로 그 신청만 본다', (tester) async {
      fake.regs
        ..add(pendingReg())
        ..add(
          Registration(
            id: 'r2',
            gatheringId: 'g1',
            phone: '01099998888',
            people: [
              Person(
                id: 'c',
                name: '김목사',
                gender: 'M',
                birthYear: 1970,
                minister: true,
                church: '새빛교회',
              ),
            ],
            quoted: 160000,
            createdAt: DateTime(2026, 9, 11),
          ),
        );
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      expect(find.text('사역자'), findsOneWidget); // 김목사 줄에만
      expect(find.byType(Checkbox), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilterChip, '사역자 1'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('김목사'), findsWidgets); // 신청자·입금자명 칸
    });

    testWidgets('신청 삭제: 확인하면 서버에서 지우고 그 신청의 참석자도 뺀다', (tester) async {
      fake.regs.add(pendingReg());
      current.value = sample();
      store.event.attendees.add(
        Attendee(
          id: 'a',
          name: '홍길동',
          gender: 'M',
          age: 30,
          registrationId: fake.regs.single.id,
          checkIn: DateTime(2026, 10, 9),
          checkOut: DateTime(2026, 10, 11),
        ),
      );
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));

      await tester.tap(find.text(fake.regs.single.applicant).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '신청 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(fake.regs, isEmpty);
      expect(store.event.attendees, isEmpty);
    });

    testWidgets('집회 설정: 고친 회비가 서버로 가고, 틀린 값은 막는다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(tester.takeException(), isNull);

      final adultFull = find.widgetWithText(TextField, '150000');
      await tester.enterText(adultFull, 'abc');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 이상의 숫자로'), findsOneWidget);
      expect(fake.gs.single.fee.full[AgeGroup.adult], 150000);

      await tester.enterText(find.widgetWithText(TextField, 'abc'), '160,000');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fake.gs.single.fee.full[AgeGroup.adult], 160000);
      expect(current.value!.fee.full[AgeGroup.adult], 160000);
      expect(store.event.name, '신촌하나교회 가족수양회');
    });

    testWidgets('집회 설정: 추가 항목을 지우고 저장하면 신청서에서 빠진다', (tester) async {
      current.value = sample()..formFields = ['교회'];
      store.event.customFields.add('교회');
      setView(tester, const Size(1400, 3000));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.byTooltip("'교회' 항목 삭제"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, '교회'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fake.gs.single.formFields, isEmpty);
      expect(store.event.customFields, isEmpty);
    });

    testWidgets('집회 설정: 계좌 없이 신청을 받으려 하면 막는다', (tester) async {
      current.value = sample()..bank = Bank();
      setView(tester, const Size(1400, 2400));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(find.text('신청을 받으려면 입금 계좌를 입력하세요.'), findsOneWidget);
    });

    testWidgets('탭 화면: 새 탭 두 개가 앞에 붙는다', (tester) async {
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Shell());
      expect(tester.takeException(), isNull);
      for (final t in ['집회 설정', '신청·입금', '방 관리', '참석자', '방배정', '자동배정', '현황']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    });
  });
}

/// 수정(update_registration)만 가로채는 가짜.
class _EditRemote extends FakeRemote {
  _EditRemote(this.base, this.updates);
  final FakeRemote base;
  final List<List<Person>> updates;

  @override
  Future<Registration?> lookup(String g, String phone, String pin) =>
      base.lookup(g, phone, pin);

  @override
  Future<Registration?> updateMine(
    String gatheringId,
    String phone,
    String pin, {
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async {
    final r = await base.lookup(gatheringId, phone, pin);
    if (r == null) return null;
    updates.add(people);
    return r
      ..people = people
      ..quoted = quoted;
  }
}
