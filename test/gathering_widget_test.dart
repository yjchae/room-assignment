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
import 'package:room_assignment/widgets/custom_field_input.dart';

/// 메모리 서버. 실제 서버 함수(supabase/schema.sql)와 같은 규칙만 흉내 낸다.
class FakeRemote extends Remote {
  FakeRemote({this.admin = true});
  bool admin;

  /// 전체 운영자인가. false 면 [managed] 집회만 맡은 집회별 운영자다.
  bool full = true;
  final managed = <String>{};

  /// [managed] 중 운영스탭으로만 맡은 집회 (집회 설정을 못 고친다).
  final staffOf = <String>{};

  /// [managed] 중 내가 만든 집회 (집회관리자 — 삭제·운영자 승인).
  final ownedSet = <String>{};

  /// 승인된 가입자(owner)인가 — 전체 운영자가 아니어도 집회를 하나 만들 수 있다.
  bool owner = false;

  /// 로그인·목록이 받은 초대 코드.
  final invites = <String>[];

  /// 집회 id → 그 집회의 운영자 (이메일).
  final gAdmins = <String, List<GatheringAdmin>>{};

  /// 가입된 계정 이메일 (집회 운영자로 등록할 수 있는 사람).
  final accounts = <String>{'helper@x'};
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
  Future<void> signIn(String email, String password, {String? invite}) async {
    if (password != 'pw') throw const RemoteError('Invalid login credentials');
    admin = true;
    await enter(invite: invite);
  }

  @override
  Future<void> enter({String? invite}) async {
    if (invite != null) invites.add(invite);
  }

  @override
  Future<String> gatheringInvite(String gatheringId, {bool renew = false}) async =>
      'https://invite/$gatheringId${renew ? '/new' : ''}';

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
  Future<void> signUp(
    String name,
    String email,
    String password, {
    String? invite,
  }) async => requests.add((
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

  /// true 면 권한 조회가 실패한다 (네트워크 문제·스키마 미적용 흉내).
  bool scopeError = false;

  @override
  Future<AdminScope> scope() async {
    if (scopeError) throw const RemoteError('서버에 연결하지 못했습니다.');
    fullAdmin = full;
    return (
      full: full,
      canCreate: full || owner,
      gatherings: {...managed},
      configures: {...managed.difference(staffOf)},
      owned: {...ownedSet},
    );
  }

  @override
  Future<List<GatheringAdmin>> gatheringAdmins(String gatheringId) async => [
    ...?gAdmins[gatheringId],
  ];

  @override
  Future<void> addGatheringAdmin(String gatheringId, String email) async {
    if (!accounts.contains(email.trim().toLowerCase())) {
      throw const RemoteError('NO_ACCOUNT');
    }
    gAdmins.putIfAbsent(gatheringId, () => []).add((
      userId: 'u-$email',
      email: email.trim(),
      role: GatheringRole.staff, // 서버처럼 운영스탭으로 시작
      approved: true, // 이메일 등록은 승인까지 끝난다
    ));
  }

  @override
  Future<void> approveGatheringAdmin(String gatheringId, String userId) async {
    final list = gAdmins[gatheringId]!;
    final i = list.indexWhere((a) => a.userId == userId);
    final a = list[i];
    list[i] = (userId: userId, email: a.email, role: a.role, approved: true);
  }

  @override
  Future<void> setGatheringAdminRole(
    String gatheringId,
    String userId,
    GatheringRole role,
  ) async {
    final list = gAdmins[gatheringId]!;
    final i = list.indexWhere((a) => a.userId == userId);
    list[i] = (
      userId: userId,
      email: list[i].email,
      role: role,
      approved: list[i].approved,
    );
  }

  @override
  Future<void> removeGatheringAdmin(String gatheringId, String userId) async =>
      gAdmins[gatheringId]?.removeWhere((a) => a.userId == userId);

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

  // 스탭 페이지. 서버(_my_duties·save_duty_items)와 같은 규칙만 흉내 낸다 —
  // 신청의 사람 id 가 담당구역의 personIds 에 있으면 그 구역이 내 것이다.
  @override
  Future<({String name, List<StaffDuty> duties})?> lookupDuties(
    String gatheringId,
    String phone,
    String pin,
  ) async {
    final r = await lookup(gatheringId, phone, pin);
    if (r == null || r.status == RegStatus.cancelled) return null;
    final mine = r.people.map((p) => p.id).toSet();
    final plan = plans[gatheringId];
    final attendees = [
      for (final a in (plan?['attendees'] as List? ?? [])) a as Map,
    ];
    return (
      name: r.applicant,
      duties: [
        for (final d in (plan?['duties'] as List? ?? []))
          if ((d as Map)['personIds'] is List &&
              (d['personIds'] as List).any(mine.contains))
            (
              duty: Duty.fromJson(Map<String, dynamic>.from(d)),
              members: [
                for (final a in attendees)
                  if ((d['personIds'] as List).contains(a['id'])) '${a['name']}',
              ],
            ),
      ],
    );
  }

  @override
  Future<bool> saveDutyItems(
    String gatheringId,
    String phone,
    String pin, {
    required String dutyId,
    required List<DutyTask> items,
  }) async {
    final me = await lookupDuties(gatheringId, phone, pin);
    if (me == null || !me.duties.any((d) => d.duty.id == dutyId)) return false;
    for (final d in (plans[gatheringId]!['duties'] as List)) {
      if ((d as Map)['id'] == dutyId) {
        d['items'] = [for (final t in items) t.toJson()];
      }
    }
    return true;
  }

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

/// 신청서는 부분 참석(날짜 직접 고르기)으로 시작하므로, 전체 참석 스위치를 켠다.
Future<void> attendAll(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(SwitchListTile, '전체 참석').first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    fake = FakeRemote()..gs.add(sample());
    remote = fake;
    current.value = null;
    passwordRecovery.value = false;
    canConfigure.value = true;
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
      await attendAll(tester);
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
      await attendAll(tester);
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
      await attendAll(tester);
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

    testWidgets('추가 항목이 형식대로 나오고 고른 값이 신청에 들어간다', (tester) async {
      setView(tester, const Size(400, 3000));
      final g = sample()
        ..requiredFields = []
        ..formFields = ['교회', '인원', '차량', '간식', '메모']
        ..fieldSpecs = {
          '교회': const FieldSpec(
            type: FieldType.select,
            options: ['A교회', 'B교회'],
          ),
          '인원': const FieldSpec(type: FieldType.number),
          '차량': const FieldSpec(type: FieldType.check),
          '간식': const FieldSpec(type: FieldType.toggle),
        };
      await pumpPage(tester, ApplyPage(gathering: g));
      expect(tester.takeException(), isNull);
      await tester.enterText(field('이름 *'), '홍길동');
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B교회').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('인원'), '3명');
      await tester.tap(find.widgetWithText(CheckboxListTile, '차량'));
      await tester.tap(find.widgetWithText(FilterChip, '간식'));
      await tester.enterText(field('메모'), '늦게 도착');
      await attendAll(tester);
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      final p = (fake.lastSubmit!['people'] as List<Person>).single;
      expect(p.extra, {
        '교회': 'B교회',
        '인원': '3',
        '차량': fieldOn,
        '간식': fieldOn,
        '메모': '늦게 도착',
      });
    });

    testWidgets('보기에서 지운 값을 가진 신청도 깨지지 않고 그 값을 보여 준다', (tester) async {
      setView(tester, const Size(400, 600));
      final c = TextEditingController(text: '옛 교회');
      await pumpPage(
        tester,
        Scaffold(
          body: CustomFieldInput(
            label: '교회',
            spec: const FieldSpec(type: FieldType.select, options: ['A교회']),
            controller: c,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('옛 교회 (목록에 없음)'), findsOneWidget);
    });

    testWidgets('숙박비 별도: 날짜 줄마다 참석·숙박을 고르고, 참가비·숙박비 합계를 보인다', (tester) async {
      setView(tester, const Size(400, 3000));
      final g = sample()
        ..requiredFields = []
        ..fee.lodgingSeparate = true
        ..fee.dayOnly[AgeGroup.adult] = 60000
        ..fee.lodging[AgeGroup.adult] = 30000;
      await pumpPage(tester, ApplyPage(gathering: g));
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(SwitchListTile, '전체 참석'), findsNothing);
      expect(find.byKey(const ValueKey('stay-2026-10-11')), findsNothing, reason: '마지막 날은 밤이 없다');
      await tester.enterText(field('이름 *'), '홍길동');
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byKey(const ValueKey('attend-all')));
      await tester.tap(find.byKey(const ValueKey('stay-2026-10-10')));
      await tester.pumpAndSettle();
      expect(find.textContaining('참가 150,000원 + 숙박 30,000원'), findsWidgets);
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(find.text('참가비 합계'), findsOneWidget);
      expect(find.text('숙박비 합계'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      final p = (fake.lastSubmit!['people'] as List<Person>).single;
      expect(p.days, isNull, reason: '전체 참석');
      expect(p.stays, [DateTime(2026, 10, 10)]);
    });

    testWidgets('숙박비 별도: 켜기 전 신청을 고치면 숙박 칸이 이어진 날 사이 밤으로 채워져 있다', (tester) async {
      setView(tester, const Size(400, 3000));
      final g = sample()..fee.lodgingSeparate = true;
      final r = pendingReg()
        ..people.first.days = [DateTime(2026, 10, 9), DateTime(2026, 10, 10)];
      await pumpPage(
        tester,
        ApplyPage(gathering: g, editing: r, phone: r.phone, pin: '1234'),
      );
      expect(tester.takeException(), isNull);
      bool? box(String key) =>
          tester.widget<Checkbox>(find.byKey(ValueKey(key)).first).value;
      expect(box('stay-2026-10-09'), isTrue);
      expect(box('stay-2026-10-10'), isFalse);
      expect(box('attend-2026-10-11'), isFalse);
    });

    testWidgets('숙박비 별도: 전체 참석에서 하루를 빼면 나머지 날만 참석', (tester) async {
      setView(tester, const Size(400, 3000));
      final g = sample()..fee.lodgingSeparate = true;
      await pumpPage(tester, ApplyPage(gathering: g));
      await tester.tap(find.byKey(const ValueKey('attend-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attend-2026-10-09')));
      await tester.tap(find.byKey(const ValueKey('stay-all')));
      await tester.pumpAndSettle();
      final attend = tester.widget<Checkbox>(
        find.byKey(const ValueKey('attend-all')),
      );
      expect(attend.value, isNull, reason: '일부만 고름');
      final stay = tester.widget<Checkbox>(
        find.byKey(const ValueKey('stay-2026-10-09')),
      );
      expect(stay.value, isTrue);
    });

    testWidgets('스탭 칸은 켠 집회에만 나오고, 필수면 체크해야 신청된다', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      expect(find.text('스탭으로 신청합니다'), findsNothing); // 기본은 안 받음

      final g = sample()
        ..requiredFields = ['staff']
        ..shownFields = ['staff'];
      await pumpPage(tester, ApplyPage(gathering: g));
      await tester.enterText(field('이름 *'), '김스탭');
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await attendAll(tester);
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(find.text('스탭 신청에 체크해야 합니다'), findsOneWidget);
      expect(fake.lastSubmit, isNull);

      await tester.tap(find.text('스탭으로 신청합니다 *'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      expect((fake.lastSubmit!['people'] as List<Person>).single.staff, isTrue);
    });

    testWidgets('스탭 페이지: 내 담당구역만 보이고, 할 일을 적어 저장한다', (tester) async {
      // 스탭 김스탭(사람 id 'p-staff')이 '주방'에 배정돼 있다. '차량'은 남의 구역.
      fake.regs.add(
        Registration(
          id: 'r-staff',
          gatheringId: 'g1',
          phone: '01012345678',
          people: [
            Person(
              id: 'p-staff',
              name: '김스탭',
              gender: 'M',
              birthYear: 1990,
              staff: true,
            ),
          ],
          status: RegStatus.confirmed,
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      fake.pins['r-staff'] = '1234';
      fake.plans['g1'] = Event(
        name: 'x',
        startDate: DateTime(2026, 10, 9),
        endDate: DateTime(2026, 10, 11),
        attendees: [
          Attendee(
            id: 'p-staff',
            name: '김스탭',
            gender: 'M',
            age: 36,
            checkIn: DateTime(2026, 10, 9),
            checkOut: DateTime(2026, 10, 11),
          )..staff = true,
        ],
        duties: [
          Duty(id: 'd1', name: '주방', tasks: '배식', personIds: ['p-staff']),
          Duty(id: 'd2', name: '차량', personIds: ['남']),
        ],
      ).toJson();

      setView(tester, const Size(400, 1600));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1', staff: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01012345678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '내 담당구역 보기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('주방'), findsOneWidget);
      expect(find.text('차량'), findsNothing); // 남의 구역은 안 보인다
      expect(find.textContaining('함께 맡은 사람: 김스탭'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '행 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '구분'), '준비물');
      await tester.enterText(find.widgetWithText(TextField, '내용'), '국자');
      await tester.enterText(find.widgetWithText(TextField, '수량'), '2');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(find.text('저장했습니다.'), findsOneWidget);

      final saved = Event.fromJson(fake.plans['g1']!).duties.first;
      expect(saved.name, '주방');
      expect(
        (saved.items.single.kind, saved.items.single.content, saved.items.single.qty),
        ('준비물', '국자', '2'),
      );
    });

    testWidgets('스탭 페이지: 담당구역이 없으면 안내하고, PIN 이 틀리면 막는다', (tester) async {
      fake.regs.add(
        Registration(
          id: 'r-x',
          gatheringId: 'g1',
          phone: '01099990000',
          people: [Person(id: 'p-x', name: '박참석', gender: 'M', birthYear: 1990)],
          status: RegStatus.confirmed,
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      fake.pins['r-x'] = '1234';
      setView(tester, const Size(400, 1200));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1', staff: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '휴대폰번호'),
        '01099990000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '9999',
      );
      await tester.tap(find.widgetWithText(FilledButton, '내 담당구역 보기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('맞지 않습니다'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'PIN (숫자 4자리)'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '내 담당구역 보기'));
      await tester.pumpAndSettle();
      expect(find.text('담당구역이 없습니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      await attendAll(tester);
      expect(find.textContaining('성인 · 전체'), findsOneWidget);
      expect(
        Gathering.fromRow({...g.toRow(), 'id': g.id}).hiddenFields,
        g.hiddenFields,
      );
    });

    testWidgets('신청서는 부분 참석으로 시작하고, 날짜를 안 고르면 막는다', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.pumpAndSettle();
      final full = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '전체 참석'),
      );
      expect(full.value, isFalse);
      // 날짜를 고르기 전엔 가족당 금액만 뜨지 않고 안내가 나온다.
      expect(find.text('참석하는 날을 고르면 금액이 계산됩니다'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      expect(find.text('참석하는 날을 하루 이상 고르세요'), findsOneWidget);
      expect(fake.lastSubmit, isNull);
    });

    testWidgets('운영자 접수는 전체 참석으로 시작한다', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample(), admin: true));
      final full = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '전체 참석'),
      );
      expect(full.value, isTrue);
    });

    testWidgets('일정 없는 날을 뺀 모든 날을 고르면 전체 참석으로 낸다', (tester) async {
      setView(tester, const Size(400, 2400));
      final g = sample()..offDays = [DateTime(2026, 10, 11)];
      await pumpPage(tester, ApplyPage(gathering: g));
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-09(금)'));
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-10(토)'));
      await tester.pumpAndSettle();
      expect(find.text('160,000원'), findsOneWidget);
      expect(find.textContaining('성인 · 전체'), findsOneWidget);
    });

    testWidgets('날짜를 안 고른 동반자가 있으면 합계 위에 안내가 남는다', (tester) async {
      setView(tester, const Size(400, 3200));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      await tester.enterText(field('출생연도 *'), '1985');
      await tester.tap(find.text('동반 참석자 추가 (가족 등)'));
      await tester.pumpAndSettle();
      await tester.enterText(field('출생연도 *').at(1), '2012');
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-09(금)').first);
      await tester.tap(find.widgetWithText(CheckboxListTile, '10-10(토)').first);
      await tester.pumpAndSettle();
      expect(find.text('참석하는 날을 고르면 금액이 계산됩니다'), findsOneWidget);
    });

    testWidgets('날짜를 고르면 1박 금액이 된다', (tester) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      await tester.enterText(field('출생연도 *'), '1985');
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
          checkIn: DateTime(2026, 10, 9),
          checkOut: DateTime(2026, 10, 10),
          nights: const [],
        ),
        // 기간을 나눠 하루만 우리 집에 묵는 조각
        (
          name: '손님2',
          gender: 'M',
          age: 30,
          phone: null,
          cell: null,
          zone: null,
          checkIn: DateTime(2026, 10, 10),
          checkOut: DateTime(2026, 10, 11),
          nights: const [],
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
      expect(find.text('2명'), findsOneWidget);
      expect(find.text('손님1'), findsOneWidget);
      expect(find.text('여 · 20세 · 믿음셀'), findsOneWidget);
      expect(find.text('010-0000-1111'), findsOneWidget);
      // 배정한 기간이 사람마다 따로 보인다
      expect(find.text('10-09(금) ~ 10-10(토) · 1박'), findsOneWidget);
      expect(find.text('10-10(토) ~ 10-11(일) · 1박'), findsOneWidget);
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
      expect(find.textContaining('전체 운영자가 승인하면'), findsOneWidget);
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

    testWidgets('집회별 운영자: 맡은 집회만 보이고 [새 집회]가 없다', (tester) async {
      fake.gs.add(
        sample()
          ..id = 'g2'
          ..name = '남의 집회',
      );
      fake
        ..full = false
        ..managed.add('g1');
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('신촌하나교회 가족수양회'), findsOneWidget);
      expect(find.text('남의 집회'), findsNothing);
      expect(find.widgetWithText(FilledButton, '새 집회'), findsNothing);
      // 가입 승인은 전체 운영자만
      await tester.tap(find.text('admin@test'));
      await tester.pumpAndSettle();
      expect(find.text('운영자 승인'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // 승인된 가입자(owner)는 전체 운영자가 아니어도 집회를 하나 만든다
      fake.owner = true;
      await tester.tap(find.byTooltip('새로고침'));
      await tester.pumpAndSettle();
      expect(find.text('남의 집회'), findsNothing);
      expect(find.widgetWithText(FilledButton, '새 집회'), findsOneWidget);

      // 전체 운영자는 전부 보고 새 집회도 만든다
      fake.full = true;
      await tester.tap(find.byTooltip('새로고침'));
      await tester.pumpAndSettle();
      expect(find.text('남의 집회'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '새 집회'), findsOneWidget);
    });

    testWidgets('집회 설정: 이메일로 이 집회의 운영자를 등록하고 해제한다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('이 집회의 운영자'), findsOneWidget);
      expect(find.textContaining('등록된 운영자가 없습니다'), findsOneWidget);


      // 가입하지 않은 이메일은 막는다
      await tester.enterText(
        find.widgetWithText(TextField, '운영자 이메일'),
        'nobody@x',
      );
      await tester.tap(find.widgetWithText(FilledButton, '운영자 등록'));
      await tester.pumpAndSettle();
      expect(find.textContaining('가입한 계정이 없습니다'), findsOneWidget);
      expect(fake.gAdmins['g1'] ?? [], isEmpty);

      // 가입한 이메일이면 등록된다
      await tester.enterText(
        find.widgetWithText(TextField, '운영자 이메일'),
        'helper@x',
      );
      await tester.tap(find.widgetWithText(FilledButton, '운영자 등록'));
      await tester.pumpAndSettle();
      expect(fake.gAdmins['g1']!.single.email, 'helper@x');
      expect(find.text('helper@x'), findsOneWidget);
      expect(fake.gAdmins['g1']!.single.role, GatheringRole.staff);

      // 보조운영자로 올린다
      await tester.tap(find.text('보조운영자'));
      await tester.pumpAndSettle();
      expect(fake.gAdmins['g1']!.single.role, GatheringRole.assistant);

      // 해제
      await tester.tap(find.widgetWithText(TextButton, '해제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '해제'));
      await tester.pumpAndSettle();
      expect(fake.gAdmins['g1'], isEmpty);
    });

    testWidgets('운영스탭: [집회 설정]이 꺼져 있고 신청·입금에서 시작한다', (tester) async {
      fake
        ..full = false
        ..managed.add('g1')
        ..staffOf.add('g1');
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('신촌하나교회 가족수양회'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tabIndex.value, registrationsTab);
      expect(find.byType(GatheringSettingsScreen), findsNothing);
      expect(find.byType(RegistrationsScreen), findsOneWidget);

      // 메뉴를 눌러도, 다른 곳에서 탭을 넘겨도 설정 화면은 안 열린다
      await tester.tap(find.text('집회 설정'));
      await tester.pumpAndSettle();
      expect(find.byType(GatheringSettingsScreen), findsNothing);
      tabIndex.value = settingsTab;
      await tester.pumpAndSettle();
      expect(find.byType(GatheringSettingsScreen), findsNothing);

      // 나머지 메뉴(방 관리 등)는 연다
      await tester.tap(find.text('방 관리'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomsScreen), findsOneWidget);
    });

    testWidgets('로그인한 채 초대 링크를 열면 승인 후 목록에 나온다고 알린다', (tester) async {
      pendingInvite = 'code-b';
      addTearDown(() => pendingInvite = null);
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      expect(fake.invites, ['code-b']);
      expect(pendingInvite, isNull);
      expect(find.textContaining('집회관리자가 승인하면 이 목록에 나옵니다'), findsOneWidget);
    });

    testWidgets('보조운영자: 집회를 열면 [집회 설정]에서 시작한다', (tester) async {
      fake
        ..full = false
        ..managed.add('g1');
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('신촌하나교회 가족수양회'));
      await tester.pumpAndSettle();
      expect(canConfigure.value, isTrue);
      expect(find.byType(GatheringSettingsScreen), findsOneWidget);
    });

    testWidgets('집회 설정: 초대 링크를 복사한다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.text('초대 링크 복사'));
      await tester.pumpAndSettle();
      expect(find.textContaining('초대 링크를 복사했습니다'), findsOneWidget);
    });

    testWidgets('집회 설정: [집회 삭제]는 전체 운영자에게만 보인다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      // 전체 운영자에게는 보여야 한다 — 이 줄이 없으면 권한을 못 읽어 숨는 버그를 못 잡는다.
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('집회 삭제'), findsWidgets);

      fake
        ..full = false
        ..managed.add('g1');
      // 같은 위젯을 다시 pump 하면 State 가 살아남아 initState 가 안 돈다. 한 번 비운다.
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('집회 삭제'), findsNothing);
      expect(find.text('이 집회의 운영자'), findsOneWidget);
      // 초대 링크도 주인만 (보조운영자가 바꾸면 집회관리자가 보낸 링크가 몰래 막힌다)
      expect(find.text('초대 링크 복사'), findsNothing);

      // 집회를 만든 집회관리자는 자기 집회를 지운다
      fake.ownedSet.add('g1');
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('집회 삭제'), findsWidgets);
    });

    testWidgets('집회 설정: 초대 링크 가입자를 승인하고, 보조운영자는 승인을 못 한다', (
      tester,
    ) async {
      current.value = sample();
      fake.gAdmins['g1'] = [
        (
          userId: 'u-new',
          email: 'new@x',
          role: GatheringRole.staff,
          approved: false,
        ),
      ];
      // 보조운영자: 대기자가 보이지만 승인·거절이 꺼져 있다
      fake
        ..full = false
        ..managed.add('g1');
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('new@x'), findsOneWidget);
      expect(find.text('승인 대기 · 초대 링크로 가입'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '승인')).onPressed,
        isNull,
      );
      expect(find.textContaining('집회관리자만 할 수 있습니다'), findsOneWidget);

      // 집회관리자(만든 사람): 승인하면 운영스탭으로 들어온다
      fake.ownedSet.add('g1');
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pumpAndSettle();
      final a = fake.gAdmins['g1']!.single;
      expect(a.approved, isTrue);
      expect(a.role, GatheringRole.staff);
      expect(find.text('승인 대기 · 초대 링크로 가입'), findsNothing);
      expect(find.text('운영스탭'), findsWidgets);
    });

    testWidgets('집회 설정: 운영자 목록을 못 읽으면 이유를 보여주고 [집회 삭제]를 숨기지 않는다', (
      tester,
    ) async {
      current.value = sample();
      fake.scopeError = true;
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.textContaining('운영자 목록을 불러오지 못했습니다'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      // 권한을 모르는 동안 전체 운영자가 삭제 카드를 잃지 않는다 (서버가 어차피 막는다)
      expect(find.text('집회 삭제'), findsWidgets);
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
      expect(g2.fee.lodgingSeparate, isFalse, reason: '새 집회도 꺼진 채로 시작');
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
      expect(g2.specOf(homestayCapacityField).type, FieldType.number);
    });

    testWidgets('신청·입금: 홈스테이는 신청만 해도 가정이 생기고, 확정하면 입금대기 표시가 사라진다', (tester) async {
      fake.gs
        ..clear()
        ..add(homestay());
      fake.regs.add(homeReg(status: RegStatus.pending));
      current.value = homestay();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      // 신청 목록을 읽자마자 입금 전 가정도 방으로 올라온다 (방배정을 미리 할 수 있게).
      expect(store.event.rooms.single.unpaid, isTrue);
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
      expect(room.pay, isNull);
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
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('일정표'), findsOneWidget);
      // 일정표의 날짜 칸 + 회비 카드의 당일 무료 칩
      expect(find.text('10-09(금)'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilterChip, '10-10(토)'));
      await tester.pumpAndSettle();
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
      expect(fake.gs.single.fee.freeDays, [DateTime(2026, 10, 10)]);
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
      // 입금 전에도 참석자로 올라와 있다 — 입금대기 표시와 함께.
      expect(store.event.attendees.map((a) => a.name), ['홍길동', '홍딸']);
      expect(store.event.attendees.every((a) => a.unpaid), isTrue);

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
      // 같은 참석자에서 입금대기 표시만 사라진다
      expect(store.event.attendees.map((a) => a.name), ['홍길동', '홍딸']);
      expect(store.event.attendees.every((a) => a.pay == null), isTrue);
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

    testWidgets('참석자: 입금 전 신청자도 열자마자 보이고, 입금확인·입금대기로 나눠 본다', (tester) async {
      fake.regs.add(pendingReg()); // 홍길동·홍딸, 입금대기
      store.event.attendees.add(
        Attendee(
          id: 'x',
          name: '직접추가',
          gender: 'M',
          age: 40,
          checkIn: DateTime(2026, 10, 9),
          checkOut: DateTime(2026, 10, 11),
        ),
      );
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: AttendeesScreen()));
      expect(tester.takeException(), isNull);

      expect(store.event.attendees.map((a) => a.name).toSet(), {
        '직접추가',
        '홍길동',
        '홍딸',
      });
      expect(find.text('입금대기'), findsNWidgets(2)); // 이름 옆 배지
      await tester.tap(find.text('입금대기 2'));
      await tester.pumpAndSettle();
      expect(find.textContaining('직접추가'), findsNothing);
      await tester.tap(find.text('입금확인 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('직접추가'), findsOneWidget);
      expect(find.textContaining('홍길동'), findsNothing);
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
      setView(tester, const Size(1400, 3600));
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

    testWidgets('집회 설정: 셀렉트박스 항목을 보기와 함께 추가하고 저장한다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.widgetWithText(ActionChip, '항목 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '항목 이름'), '교회');
      await tester.tap(find.widgetWithText(ChoiceChip, '셀렉트박스'));
      await tester.pumpAndSettle();
      FilledButton add() =>
          tester.widget(find.widgetWithText(FilledButton, '추가'));
      expect(add().onPressed, isNull, reason: '보기 없이는 못 만든다');
      expect(find.text('보기를 하나 이상 적으세요.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '보기 1'), 'A교회');
      await tester.tap(find.text('보기 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '보기 2'), 'B교회');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('교회 · 셀렉트박스(2)'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(fake.gs.single.formFields, ['교회']);
      expect(
        fake.gs.single.specOf('교회'),
        const FieldSpec(type: FieldType.select, options: ['A교회', 'B교회']),
      );
    });

    testWidgets('집회 설정: 항목을 눌러 형식을 바꾼다', (tester) async {
      current.value = sample()..formFields = ['차량'];
      store.event.customFields.add('차량');
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.widgetWithText(InputChip, '차량'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '토글 버튼'));
      await tester.pumpAndSettle();
      expect(find.text('이미 받은 값은 그대로 둡니다.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '저장').last);
      await tester.pumpAndSettle();
      expect(store.event.specOf('차량').type, FieldType.toggle);
      expect(find.text('차량 · 토글 버튼'), findsOneWidget);
    });

    testWidgets('집회 설정: 기존 집회에도 숙박비 별도 스위치가 꺼진 채로 있다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '숙박비 별도'),
      );
      expect(sw.value, isFalse);
      expect(find.text('1박당 (부분 참석)'), findsOneWidget);
      // 켜지 않고 저장하면 회비 JSON 에 새 키가 생기지 않는다.
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(fake.gs.single.fee.toJson().containsKey('lodgingSeparate'), isFalse);
    });

    testWidgets('집회 설정: 기존 집회에서 숙박비 별도를 켜고 연령별 숙박비를 저장한다', (tester) async {
      current.value = fake.gs.single.copy();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('숙박 1박'), findsNothing);
      await tester.tap(find.widgetWithText(SwitchListTile, '숙박비 별도'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('숙박 1박'), findsOneWidget);
      expect(find.text('하루 참가'), findsOneWidget);
      expect(find.text('1박당 (부분 참석)'), findsNothing);
      // 숙박 1박 열(성인 줄 = 첫 번째 '0' 힌트 칸들 중 숙박 열)에 금액을 넣는다.
      final adultLodging = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.controller != null &&
            w.decoration?.suffixText == '원' &&
            w.decoration?.hintText == '0',
      );
      // 성인 줄: [하루 참가, 숙박 1박] 순서.
      await tester.enterText(adultLodging.at(1), '30000');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      final saved = fake.gs.single.fee;
      expect(saved.lodgingSeparate, isTrue);
      expect(saved.lodging[AgeGroup.adult], 30000);
      expect(saved.perNight[AgeGroup.adult], 70000, reason: '숨긴 1박당 금액은 지우지 않는다');
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

  // 날짜 없이 신청 받기 (PLAN_GATHERING §25). 모든 분기는 dateless 일 때만 —
  // 같은 화면을 날짜 있는 집회로 그리면 예전 그대로여야 한다.
  group('날짜 없이 신청 받기', () {
    Gathering dateless() => sample()
      ..dateless = true
      ..end = DateTime(2026, 10, 9);

    Future<void> fillPerson(WidgetTester tester, int i, String name) async {
      await tester.enterText(field('이름 *').at(i), name);
      await tester.enterText(field('출생연도 *').at(i), '1985');
      await tester.tap(find.text('남').at(i));
      await tester.pumpAndSettle();
    }

    testWidgets('신청서: [참가][미참가]만 있고, 참가 2·미참가 1 이 days null/null/[] 로 간다', (
      tester,
    ) async {
      setView(tester, const Size(400, 4000));
      await pumpPage(tester, ApplyPage(gathering: dateless()));
      expect(tester.takeException(), isNull);
      expect(find.text('참가 여부'), findsOneWidget);
      expect(find.widgetWithText(SegmentedButton<bool>, '참가'), findsOneWidget);
      expect(find.text('미참가'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, '전체 참석'), findsNothing);
      expect(find.textContaining('참석하는 날을'), findsNothing);
      // 새 신청서는 [참가]가 골라져 있다.
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );

      await fillPerson(tester, 0, '홍길동');
      expect(find.text('성인 · 참가 · 150,000원'), findsOneWidget);
      for (final (i, n) in ['홍동생', '홍미참'].indexed) {
        await tester.tap(find.text('동반 참석자 추가 (가족 등)'));
        await tester.pumpAndSettle();
        await fillPerson(tester, i + 1, n);
      }
      // 동반자도 [참가]로 시작한다. 셋째를 미참가로.
      await tester.tap(find.text('미참가').last);
      await tester.pumpAndSettle();
      expect(find.text('미참가 · 0원'), findsOneWidget);
      expect(find.text('310,000원'), findsOneWidget); // 150,000 × 2 + 가족당 10,000

      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byType(CheckboxListTile).last); // 개인정보 동의
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final s = fake.lastSubmit!;
      final people = s['people'] as List<Person>;
      expect(people.map((p) => p.name), ['홍길동', '홍동생', '홍미참']);
      expect(people.map((p) => p.days), [null, null, <DateTime>[]]);
      expect(s['quoted'], 310000);
    });

    testWidgets('신청서: 모두 미참가면 0원, 완료 화면에 계좌가 없다', (tester) async {
      setView(tester, const Size(400, 3000));
      await pumpPage(tester, ApplyPage(gathering: dateless()));
      await fillPerson(tester, 0, '홍길동');
      await tester.tap(find.text('미참가'));
      await tester.pumpAndSettle();
      await tester.enterText(field('휴대폰번호 *'), '010-1234-5678');
      await tester.enterText(field('조회용 PIN (숫자 4자리) *'), '1234');
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '신청'));
      await tester.pumpAndSettle();
      expect(fake.lastSubmit!['quoted'], 0);
      expect(find.text('신청이 접수되었습니다'), findsOneWidget);
      expect(find.text('입금 계좌'), findsNothing);
    });

    testWidgets('날짜 있는 집회의 같은 신청서는 예전 그대로 (전체 참석 스위치, [참가] 없음)', (
      tester,
    ) async {
      setView(tester, const Size(400, 2400));
      await pumpPage(tester, ApplyPage(gathering: sample()));
      expect(find.widgetWithText(SwitchListTile, '전체 참석'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('참가 여부'), findsNothing);
      expect(find.text('미참가'), findsNothing);
      // 하루짜리(날짜 있는) 집회도 그대로 — 스위치가 꺼진 채 고정.
      await pumpPage(
        tester,
        ApplyPage(
          key: const ValueKey('one-day'),
          gathering: sample()..end = DateTime(2026, 10, 9),
        ),
      );
      expect(find.widgetWithText(SwitchListTile, '전체 참석'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
    });

    testWidgets('집회 페이지: 날짜 줄·일정이 없고 회비는 참가비 한 열', (tester) async {
      fake.gs
        ..clear()
        ..add(
          dateless()
            ..schedule = [
              (date: DateTime(2026, 10, 9), time: '19:00', title: '저녁 집회'),
            ],
        );
      setView(tester, const Size(400, 1400));
      await tester.pumpWidget(const PublicApp(gatheringId: 'g1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('참가비'), findsOneWidget);
      expect(find.text('전체 참석'), findsNothing);
      expect(find.text('당일'), findsNothing);
      expect(find.text('저녁 집회'), findsNothing);
      expect(find.textContaining('10-09'), findsNothing);
      expect(find.textContaining('부분 참석'), findsNothing);
      expect(find.textContaining('모두 미참가면 받지 않습니다'), findsOneWidget);
    });

    testWidgets('방 관리: 이름 방을 만들고, 같은 이름은 막고, 범위도 된다', (tester) async {
      current.value = dateless();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RoomsScreen()));
      Future<void> add(String v) async {
        // 앞 알림이 사라진 뒤 다음 알림이 뜬다.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '방 추가'));
        await tester.pumpAndSettle();
        expect(find.text('범위 가능: 301-310 · 이름도 됩니다: 1조, 찬양팀'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, '방·그룹 이름'), v);
        await tester.tap(find.widgetWithText(FilledButton, '저장'));
        await tester.pumpAndSettle();
      }

      await add('1조');
      expect(store.event.rooms.map((r) => r.roomNo), ['1조']);
      expect(find.text('1조 방을 추가했습니다.'), findsOneWidget);
      await add('1조');
      expect(store.event.rooms, hasLength(1));
      expect(find.text('1조 방이 이미 있습니다.'), findsOneWidget);
      await add('301-303');
      expect(store.event.rooms, hasLength(4));
    });

    testWidgets('방 관리: 날짜 있는 집회는 예전처럼 호수만 받는다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RoomsScreen()));
      await tester.tap(find.widgetWithText(FilledButton, '방 추가'));
      await tester.pumpAndSettle();
      expect(find.text('범위 가능: 301-310, 401'), findsOneWidget);
      expect(find.widgetWithText(TextField, '방·그룹 이름'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, '호수'), '1조');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(store.event.rooms, isEmpty);
      expect(find.text('호수를 인식하지 못했습니다. 예: 301 또는 301-310'), findsOneWidget);
    });

    testWidgets('방 관리: 사용 기간을 줄이면 묻고, 배정된 사람의 남은 기간을 미배정으로 나눈다', (
      tester,
    ) async {
      current.value = sample();
      store.event.rooms.add(Room(id: 'A', roomNo: '301', capacity: 4));
      store.event.attendees.add(
        Attendee(
          id: 'p1',
          name: '김철수',
          gender: 'M',
          age: 30,
          roomId: 'A',
          checkIn: DateTime(2026, 10, 9),
          checkOut: DateTime(2026, 10, 11),
        ),
      );
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RoomsScreen()));
      await tester.tap(find.text('301'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기간 지정'));
      await tester.pumpAndSettle();
      // 비우는 날을 10일로 — 첫 밤만 이 방을 쓴다.
      await tester.tap(find.text('비우는 날'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('1박'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(find.text('기간 밖에도 묵는 사람이 있습니다'), findsOneWidget);
      expect(find.text('김철수'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '나누고 저장'));
      await tester.pumpAndSettle();

      final room = store.event.rooms.single;
      expect(room.hostTo, DateTime(2026, 10, 10));
      expect(store.event.attendees, hasLength(2));
      expect(store.occupantsOf(room).single.checkOut, DateTime(2026, 10, 10));
      expect(store.unassigned.single.checkIn, DateTime(2026, 10, 10));
      expect(find.textContaining('1명의 남은 기간은 미배정입니다'), findsOneWidget);
    });

    testWidgets('방 관리: 날짜 없는 집회에는 사용 기간 칸이 없다', (tester) async {
      current.value = dateless();
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RoomsScreen()));
      await tester.tap(find.widgetWithText(FilledButton, '방 추가'));
      await tester.pumpAndSettle();
      expect(find.text('기간 지정'), findsNothing);
    });

    testWidgets('새 집회: 체크하면 기준일 하나, 만들면 dateless·start = end, 날짜 규칙은 끈다', (
      tester,
    ) async {
      fake.gs.first
        ..fee.fullDiscountPct = 10
        ..fee.freeDays = [DateTime(2026, 10, 10)];
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('새 집회'));
      await tester.pumpAndSettle();
      // 홈스테이에는 없고, 갔다 오면 꺼져 있다.
      await tester.tap(find.text('홈스테이'));
      await tester.pumpAndSettle();
      expect(find.text('날짜 없이 신청 받기'), findsNothing);
      await tester.tap(find.text('집회').last);
      await tester.pumpAndSettle();
      final box = find.widgetWithText(CheckboxListTile, '날짜 없이 신청 받기');
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      expect(find.text('기간'), findsOneWidget);

      // 설정을 복사해도 날짜에 붙는 회비 규칙은 끈다.
      await tester.tap(find.byType(DropdownButtonFormField<Gathering?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('신촌하나교회 가족수양회 (').last);
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(find.text('기준일'), findsOneWidget);
      expect(find.text('기간'), findsNothing);
      await tester.tap(find.text('만들기'));
      await tester.pumpAndSettle();

      final g2 = fake.gs.firstWhere((g) => g.id != 'g1');
      expect(g2.dateless, isTrue);
      expect(g2.start, g2.end);
      expect(g2.fee.lodgingSeparate, isFalse);
      expect(g2.fee.fullDiscountPct, 0);
      expect(g2.fee.freeDays, isEmpty);
      expect(fake.gs.first.dateless, isFalse, reason: '원본은 그대로');
    });

    testWidgets('집회 목록: 날짜 없는 집회 카드는 참가 신청 · 기준일, 날짜 있는 집회는 그대로', (
      tester,
    ) async {
      fake.gs.add(
        dateless()
          ..id = 'g2'
          ..name = '참가 조사',
      );
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      expect(find.text('참가 신청 · 기준일 2026-10-09(금)'), findsOneWidget);
      expect(find.text('날짜 없음'), findsOneWidget);
      expect(find.text('2026-10-09(금) ~ 10-11(일) · 2박3일'), findsOneWidget);
    });

    testWidgets('신청·입금: 참가 n · 미참가 m, 전원 미참가는 무료', (tester) async {
      final g = dateless();
      fake.gs
        ..clear()
        ..add(g);
      fake.regs
        ..add(
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
                birthYear: 1990,
                days: [],
              ),
            ],
            quoted: 160000,
            createdAt: DateTime(2026, 9, 10),
          ),
        )
        ..add(
          Registration(
            id: 'r2',
            gatheringId: 'g1',
            phone: '01099998888',
            people: [
              Person(
                id: 'c',
                name: '김미참',
                gender: 'M',
                birthYear: 1985,
                days: [],
              ),
            ],
            quoted: 0,
            createdAt: DateTime(2026, 9, 10),
          ),
        );
      current.value = g;
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: RegistrationsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('참가 1 · 미참가 1'), findsOneWidget);
      expect(find.text('미참가 1'), findsOneWidget);
      expect(find.text('무료'), findsOneWidget);
    });

    testWidgets('집회 설정: 날짜 없음 칩·기준일, 일정표·전체 참석 할인·1박·당일 열 없음', (tester) async {
      final g = dateless()
        ..fee.fullDiscountPct = 10
        ..end = DateTime(2026, 10, 11); // 어긋난 end 도 저장하면 start 로 맞춘다
      fake.gs
        ..clear()
        ..add(g);
      current.value = g;
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('날짜 없음'), findsOneWidget);
      expect(find.text('기준일 2026-10-09(금)'), findsOneWidget);
      expect(find.text('일정표'), findsNothing);
      expect(find.text('전체 참석 할인'), findsNothing);
      expect(find.text('숙박비 별도'), findsNothing);
      expect(find.text('당일 무료인 날'), findsNothing);
      expect(find.text('참가비'), findsOneWidget);
      expect(find.text('1박당 (부분 참석)'), findsNothing);
      expect(find.text('당일'), findsNothing);
      expect(find.text('사전등록 할인'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      final saved = fake.gs.single;
      expect(saved.dateless, isTrue);
      expect(saved.end, saved.start);
      expect(saved.fee.fullDiscountPct, 0);
      expect(saved.fee.full[AgeGroup.adult], 150000);
    });

    testWidgets('집회 설정: 날짜 있는 집회는 예전 그대로', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      expect(find.text('날짜 없음'), findsNothing);
      expect(find.textContaining('기준일'), findsNothing);
      expect(find.text('일정표'), findsOneWidget);
      expect(find.text('전체 참석 할인'), findsOneWidget);
      expect(find.text('참가비'), findsNothing);
      expect(find.text('1박당 (부분 참석)'), findsOneWidget);
    });

    testWidgets('새 집회: 1박당·당일 값이 있는 집회를 복사해 날짜 없이 만들면 그 값을 비운다', (tester) async {
      fake.gs.first.fee.lodging = {AgeGroup.adult: 20000};
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const GatheringsScreen());
      await tester.tap(find.text('새 집회'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Gathering?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('신촌하나교회 가족수양회 (').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, '날짜 없이 신청 받기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('만들기'));
      await tester.pumpAndSettle();

      final g2 = fake.gs.firstWhere((g) => g.id != 'g1');
      expect(g2.fee.perNight, isEmpty);
      expect(g2.fee.dayOnly, isEmpty);
      expect(g2.fee.lodging, isEmpty);
      expect(g2.fee.full[AgeGroup.adult], 150000, reason: '참가비는 복사');
      expect(fake.gs.first.fee.perNight[AgeGroup.adult], 70000, reason: '원본은 그대로');
    });

    testWidgets('집회 설정: 날짜 없는 집회는 숨긴 1박당·당일을 비우고, 참가비를 비우면 무료', (tester) async {
      final g = dateless()..fee.perRegistration = 0; // sample 의 1박당·당일 값이 남아 있다
      fake.gs
        ..clear()
        ..add(g);
      current.value = g;
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      for (final v in ['150000', '120000', '100000', '60000']) {
        await tester.enterText(find.widgetWithText(TextField, v), '');
      }
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final saved = fake.gs.single.fee;
      expect(saved.perNight, isEmpty);
      expect(saved.dayOnly, isEmpty);
      expect(saved.lodging, isEmpty);
      expect(saved.isFree, isTrue);
      expect(saved.fullPrice(AgeGroup.adult, 0), 0);
    });

    testWidgets('집회 설정: 날짜 있는 집회는 저장해도 1박당·당일 값을 그대로 둔다', (tester) async {
      current.value = sample();
      setView(tester, const Size(1400, 3600));
      await pumpPage(tester, const Scaffold(body: GatheringSettingsScreen()));
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      final saved = fake.gs.single.fee;
      expect(saved.perNight, {AgeGroup.adult: 70000, AgeGroup.youth: 60000});
      expect(saved.dayOnly, {AgeGroup.adult: 30000});
      expect(saved.full[AgeGroup.adult], 150000);
    });

    testWidgets('조회: 참가 여부가 보이고, [수정]하면 낸 대로 되살아나 그대로 저장된다', (tester) async {
      final g = dateless();
      fake.gs
        ..clear()
        ..add(g);
      final people = [
        Person(id: 'a', name: '홍길동', gender: 'M', birthYear: 1985),
        Person(id: 'b', name: '홍미참', gender: 'M', birthYear: 1985, days: []),
      ];
      fake.regs.add(
        Registration(
          id: 'r1',
          gatheringId: 'g1',
          phone: '01012345678',
          people: people,
          quoted: 160000,
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      fake.pins['r1'] = '1234';
      final updates = <List<Person>>[];
      remote = _EditRemote(fake, updates);
      setView(tester, const Size(400, 3000));
      await pumpPage(tester, LookupPage(gathering: g));
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
      expect(find.text('참가 여부'), findsOneWidget);
      expect(find.text('전체 참석'), findsNothing);
      expect(find.text('참석하는 날이 없습니다.'), findsNothing);
      final miss = tester.widget<Text>(find.text('미참가').last);
      expect(miss.style?.color, AppColors.textMuted);

      await tester.tap(find.text('신청 내용 수정'));
      await tester.pumpAndSettle();
      final segs = tester
          .widgetList<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .map((b) => b.selected)
          .toList();
      expect(segs, [
        {true},
        {false},
      ]);
      await tester.tap(find.widgetWithText(FilledButton, '수정 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '수정'));
      await tester.pumpAndSettle();
      expect(updates.single.map((p) => p.days), [null, <DateTime>[]]);
    });

    testWidgets('참석자: 날짜 세그먼트 없이 참가자만 들어오고, 편집 창에 묵는 기간이 없다', (tester) async {
      final g = dateless();
      fake.gs
        ..clear()
        ..add(g);
      fake.regs.add(
        Registration(
          id: 'r1',
          gatheringId: 'g1',
          phone: '01012345678',
          people: [
            Person(id: 'a', name: '홍길동', gender: 'M', birthYear: 1985),
            Person(
              id: 'b',
              name: '홍미참',
              gender: 'M',
              birthYear: 1985,
              days: [],
            ),
          ],
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      current.value = g;
      store.applyGathering(g);
      setView(tester, const Size(1400, 900));
      await pumpPage(tester, const Scaffold(body: AttendeesScreen()));
      expect(tester.takeException(), isNull);
      expect(store.event.attendees.map((a) => a.name), ['홍길동']);
      expect(find.textContaining('합계'), findsNothing);
      expect(find.textContaining('전참'), findsNothing);
      expect(find.text('당일'), findsNothing);

      await tester.tap(find.textContaining('홍길동').first);
      await tester.pumpAndSettle();
      expect(find.text('묵는 기간'), findsNothing);
      expect(find.text('체크인'), findsNothing);
      expect(find.text('체크아웃'), findsNothing);
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
