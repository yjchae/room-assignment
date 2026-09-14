// 새 화면들 — 신청 웹(휴대폰 폭)과 관리자 화면. 서버는 가짜로 바꿔 끼운다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/main_public.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/screens/gathering_settings.dart';
import 'package:room_assignment/screens/gatherings.dart';
import 'package:room_assignment/screens/registrations.dart';
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
      await tester.tap(find.byType(CheckboxListTile));
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
      // 조회 화면의 금액표에 반영 ("홍막내  영유아 · 전체" 한 줄)
      expect(find.textContaining('홍막내'), findsOneWidget);
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
      setView(tester, const Size(1400, 900));
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
      setView(tester, const Size(1400, 900));
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
