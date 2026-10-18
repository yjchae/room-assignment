// 매뉴얼 스크린샷. 가짜 서버에 샘플 집회를 넣고 화면마다 PNG 로 찍는다 (사람 이름은 모두 지어낸 것).
// 다시 찍기: flutter test --update-goldens tool/manual/shots_test.dart
// → docs/manual/img/*.png. CI 는 test/ 만 돌리므로 여기는 안 돈다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/main_public.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/theme.dart';

import '../../test/gathering_widget_test.dart' show FakeRemote;

class ShotRemote extends FakeRemote {
  @override
  Future<Map<String, ({int total, int confirmed})>>
  registrationCounts() async => {
    for (final g in gs)
      g.id: (
        total: regs.where((r) => r.gatheringId == g.id).length,
        confirmed: regs
            .where(
              (r) => r.gatheringId == g.id && r.status == RegStatus.confirmed,
            )
            .length,
      ),
  };
}

final _shot = GlobalKey();
late ShotRemote fake;

// 신청 받는 중으로 보이게 오늘(DateTime.now) 뒤 날짜로 둔다. 지나면 날짜만 옮긴다.
final d9 = DateTime(2026, 11, 13), d10 = DateTime(2026, 11, 14);
final d11 = DateTime(2026, 11, 15);

Gathering gathering() => Gathering(
  id: 'g1',
  name: '2026 가을 가족수양회',
  start: d9,
  end: d11,
  themes: ['회복', '다음세대'],
  place: '가평 은혜수양관',
  address: '경기도 가평군 가평읍',
  notice: '준비물: 성경, 필기도구, 세면도구\n문의: 교육부 010-0000-0000',
  open: true,
  deadline: DateTime(2026, 11, 8),
  shownFields: ['staff'],
  formFields: ['교회'],
  schedule: [
    (date: d9, time: '15:00', title: '등록 · 입실'),
    (date: d9, time: '19:30', title: '개회예배'),
    (date: d10, time: '07:00', title: '새벽기도'),
    (date: d10, time: '10:00', title: '주제강의 1'),
    (date: d10, time: '19:30', title: '저녁집회'),
    (date: d11, time: '10:00', title: '폐회예배'),
  ],
  bank: Bank(bank: '국민', account: '123-45-678901', holder: '가을수양회'),
  fee: FeeRule(
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
    },
    dayOnly: {AgeGroup.adult: 30000, AgeGroup.youth: 20000},
    perRegistration: 10000,
    early: [(fromDays: 30, toDays: 14, pct: 10)],
  ),
);

/// (성, [가족: 이름, 성별, 출생연도]) — 모두 지어낸 이름.
const _families = [
  ('김', [('민준', 'M', 1982), ('서연', 'F', 1984), ('하윤', 'F', 2014)]),
  ('이', [('도윤', 'M', 1990), ('지우', 'F', 1991)]),
  ('박', [('서준', 'M', 1975), ('수아', 'F', 1977), ('지호', 'M', 2009), ('예린', 'F', 2012)]),
  ('최', [('예준', 'M', 1995)]),
  ('정', [('하은', 'F', 1988), ('시우', 'M', 2016)]),
  ('강', [('주원', 'M', 1968), ('미경', 'F', 1970)]),
  ('조', [('유나', 'F', 2001)]),
  ('윤', [('건우', 'M', 1985), ('소윤', 'F', 1986), ('준서', 'M', 2018)]),
  ('장', [('현우', 'M', 1999)]),
  ('임', [('다은', 'F', 1993), ('채원', 'F', 1996)]),
  ('한', [('승민', 'M', 1979), ('지민', 'F', 1981), ('윤호', 'M', 2011)]),
  ('오', [('태윤', 'M', 2003)]),
  ('서', [('은서', 'F', 1997)]),
  ('신', [('동현', 'M', 1972), ('혜진', 'F', 1974)]),
];

List<Registration> registrations() => [
  for (final (i, (last, members)) in _families.indexed)
    Registration(
      id: 'r$i',
      gatheringId: 'g1',
      phone: '010000000${i.toString().padLeft(2, '0')}',
      people: [
        for (final (j, (first, gender, year)) in members.indexed)
          Person(
            id: 'p$i-$j',
            name: '$last$first',
            gender: gender,
            birthYear: year,
            relation: j == 0 ? '본인' : (year > 2005 ? '자녀' : '배우자'),
            cell: '${i % 4 + 1}셀',
            zone: ['A', 'B', 'C'][i % 3],
            staff: j == 0 && i % 3 == 0,
            minister: i == 5 && j == 0,
            church: i == 5 && j == 0 ? '은혜교회' : null,
            days: i == 3 ? [d10, d11] : (i == 12 ? [d10] : null),
            extra: {'교회': i == 5 ? '은혜교회' : '하나교회'},
          ),
      ],
      depositor: i == 4 ? '정하은엄마' : null,
      status: i < 9
          ? RegStatus.confirmed
          : (i == 13 ? RegStatus.cancelled : RegStatus.pending),
      createdAt: DateTime(2026, 10, 1 + i),
    ),
];

Future<void> _fonts() async {
  final p = FontLoader(appFont);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    p.addFont(rootBundle.load('assets/fonts/Pretendard-$w.otf'));
  }
  await p.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Widget _app(Widget home, {bool public = false}) => RepaintBoundary(
  key: _shot,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: public
        ? buildAppTheme().copyWith(visualDensity: VisualDensity.standard)
        : buildAppTheme(),
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ),
);

Future<void> shot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus(); // 버튼에 포커스 테두리가 찍히지 않게
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(_shot),
    matchesGoldenFile('../../docs/manual/img/$name.png'),
  );
}

void desktop(WidgetTester t) {
  t.view.physicalSize = const Size(1440, 900) * 1.5;
  t.view.devicePixelRatio = 1.5;
}

void phone(WidgetTester t, {double h = 844}) {
  t.view.physicalSize = Size(390, h) * 2;
  t.view.devicePixelRatio = 2;
}

/// 확정 신청 → 참석자, 방 만들고 일부 배정, 담당구역까지 채운 방배정.
Future<void> seedPlan() async {
  final g = gathering();
  await store.open(
    g.id,
    Event(name: g.name, startDate: d9, endDate: d11, customFields: ['교회']),
  );
  current.value = g;
  store.applyGathering(g);
  if (store.event.rooms.isEmpty) {
    store.syncRegistrations(g, fake.regs);
    store.addRoomRange('201-206', capacity: 4, building: '본관');
    store.addRoomRange('301-306', capacity: 6, building: '본관');
    final rooms = store.event.rooms;
    for (final r in rooms.take(3)) {
      r.gender = 'M';
    }
    for (final r in rooms.skip(3).take(3)) {
      r.gender = 'F';
    }
    final men = store.event.attendees.where((a) => a.gender == 'M').toList();
    final women = store.event.attendees.where((a) => a.gender == 'F').toList();
    store.assignAll(men.take(4), rooms[0].id);
    store.assignAll(men.skip(4).take(3), rooms[1].id);
    store.assignAll(women.take(4), rooms[3].id);
    store.assignAll(women.skip(4).take(2), rooms[4].id);
    store.addDuty(
      Duty(
        id: 'd1',
        name: '주방',
        tasks: '식사 준비 · 배식 · 뒷정리',
        capacity: 4,
        personIds: ['p0-0', 'p3-0', 'p6-0'],
        items: [
          DutyTask(id: 't1', kind: '식재료', content: '쌀', qty: '20kg', done: true),
          DutyTask(id: 't2', kind: '식재료', content: '김치', qty: '10kg'),
          DutyTask(id: 't3', kind: '비품', content: '일회용 장갑', qty: '2상자'),
        ],
      ),
    );
    store.addDuty(
      Duty(
        id: 'd2',
        name: '차량',
        tasks: '역 픽업 · 주차 안내',
        capacity: 2,
        personIds: ['p9-0'],
      ),
    );
    store.addDuty(Duty(id: 'd3', name: '등록대', tasks: '명찰 · 회비 확인'));
    await store.pendingWrites;
  }
}

Future<void> openShell(WidgetTester tester, int tab) async {
  await seedPlan();
  tabIndex.value = tab;
  await tester.pumpWidget(_app(const Shell()));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(_fonts);
  setUp(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    fake = ShotRemote()
      ..gs.add(gathering())
      ..gs.add(
        Gathering(
          id: 'g0',
          name: '2026 여름 청년수련회',
          start: DateTime(2026, 7, 27),
          end: DateTime(2026, 7, 29),
        ),
      )
      ..gs.add(
        Gathering(
          id: 'h1',
          name: '겨울 선교 홈스테이',
          kind: GatheringKind.homestay,
          start: DateTime(2027, 1, 15),
          end: DateTime(2027, 1, 18),
          open: true,
        ),
      )
      ..regs.addAll(registrations());
    for (final r in fake.regs) {
      fake.pins[r.id] = '1234';
      r.quoted = gathering().quoteFor(r.people, r.createdAt).beforeDiscount;
      if (r.status == RegStatus.confirmed) {
        r.paid = gathering().quoteFor(r.people, r.createdAt).total;
        r.paidAt = DateTime(2026, 10, 16);
      }
    }
    fake.accounts.add('helper@example.com');
    fake.gAdmins['g1'] = [(userId: 'u1', email: 'helper@example.com')];
    remote = fake;
    current.value = null;
    store.event = Event(name: 'x', startDate: d9, endDate: d11);
  });

  group('운영자', () {
    testWidgets('로그인', (t) async {
      desktop(t);
      fake.admin = false;
      await t.pumpWidget(_app(const Gate()));
      await shot(t, 'admin_login');
      await tap(t, find.text('운영자 가입 신청'));
      await shot(t, 'admin_signup');
    });

    testWidgets('집회 목록 · 새 집회', (t) async {
      desktop(t);
      await t.pumpWidget(_app(const Gate()));
      await shot(t, 'admin_gatherings');
      await tap(t, find.text('새 집회'));
      await shot(t, 'admin_new_gathering');
    });

    testWidgets('계정 메뉴', (t) async {
      desktop(t);
      await t.pumpWidget(_app(const Gate()));
      await t.pumpAndSettle();
      await tap(t, find.byTooltip('운영자 계정'));
      await shot(t, 'admin_account_menu');
    });

    testWidgets('집회 설정', (t) async {
      desktop(t);
      t.view.physicalSize = const Size(1440, 3600) * 1.5;
      await openShell(t, settingsTab);
      await shot(t, 'admin_settings');
    });

    testWidgets('신청·입금', (t) async {
      desktop(t);
      t.view.physicalSize = const Size(1440, 1150) * 1.5;
      await openShell(t, registrationsTab);
      await shot(t, 'admin_registrations');
      await tap(t, find.text('한승민'));
      await shot(t, 'admin_registration_detail');
      await t.tap(find.text('입금 확인').last);
      await shot(t, 'admin_confirm_payment');
    });

    testWidgets('신청 추가', (t) async {
      desktop(t);
      await openShell(t, registrationsTab);
      await tap(t, find.text('신청 추가'));
      await shot(t, 'admin_add_registration');
    });

    testWidgets('방 관리', (t) async {
      desktop(t);
      await openShell(t, 2);
      await shot(t, 'admin_rooms');
      await tap(t, find.text('방 추가'));
      await shot(t, 'admin_room_add');
    });

    testWidgets('참석자', (t) async {
      desktop(t);
      await openShell(t, 3);
      await shot(t, 'admin_attendees');
    });

    testWidgets('방배정', (t) async {
      desktop(t);
      await openShell(t, assignTab);
      await tap(t, find.byType(Checkbox).at(2));
      await tap(t, find.byType(Checkbox).at(3));
      await tap(t, find.text('302'));
      await shot(t, 'admin_assign');
    });

    testWidgets('자동배정', (t) async {
      desktop(t);
      t.view.physicalSize = const Size(1440, 1100) * 1.5;
      await openShell(t, 5);
      await shot(t, 'admin_auto_assign');
      await tap(t, find.textContaining('미리보기'));
      await shot(t, 'admin_auto_preview');
    });

    testWidgets('현황', (t) async {
      desktop(t);
      await openShell(t, 6);
      await shot(t, 'admin_status');
    });

    testWidgets('담당구역', (t) async {
      desktop(t);
      await openShell(t, dutiesTab);
      await shot(t, 'admin_duties');
      await tap(t, find.text('인원 배정'));
      await shot(t, 'admin_duty_members');
    });

    testWidgets('구역 할일', (t) async {
      desktop(t);
      await openShell(t, dutyTasksTab);
      await shot(t, 'admin_duty_tasks');
    });

    testWidgets('백업 메뉴', (t) async {
      desktop(t);
      await openShell(t, 6);
      await tap(t, find.byTooltip('방배정 백업'));
      await shot(t, 'admin_backup_menu');
    });
  });

  group('운영자 (휴대폰)', () {
    testWidgets('메뉴 · 신청 · 방배정', (t) async {
      phone(t);
      await openShell(t, registrationsTab);
      await shot(t, 'admin_phone_registrations');
      await tap(t, find.byTooltip('메뉴'));
      await shot(t, 'admin_phone_drawer');
      await t.pumpWidget(const SizedBox());
      await openShell(t, 2);
      await shot(t, 'admin_phone_rooms');
    });
  });

  group('신청자', () {
    testWidgets('집회 페이지', (t) async {
      phone(t, h: 2300);
      await t.pumpWidget(_app(const GatheringPage(id: 'g1'), public: true));
      await shot(t, 'user_gathering');
    });

    testWidgets('신청서', (t) async {
      phone(t, h: 2000);
      await t.pumpWidget(_app(const GatheringPage(id: 'g1'), public: true));
      await t.pumpAndSettle();
      await tap(t, find.text('신청하기'));
      await shot(t, 'user_form');
    });

    testWidgets('조회', (t) async {
      phone(t, h: 2300);
      await t.pumpWidget(_app(const GatheringPage(id: 'g1'), public: true));
      await t.pumpAndSettle();
      await tap(t, find.text('신청 조회 · 수정'));
      phone(t);
      await shot(t, 'user_lookup');
      await t.enterText(find.byType(TextField).at(0), '01000000009');
      await t.enterText(find.byType(TextField).at(1), '1234');
      await tap(t, find.widgetWithText(FilledButton, '조회'));
      phone(t, h: 1300);
      await shot(t, 'user_lookup_result');
    });

    testWidgets('스탭 페이지', (t) async {
      phone(t);
      await seedPlan(); // 담당구역이 든 방배정을 서버에 올려 둔다
      await t.pumpWidget(_app(const StaffPage(id: 'g1'), public: true));
      await t.pumpAndSettle();
      await shot(t, 'staff_login');
      await t.enterText(find.byType(TextField).at(0), '01000000000');
      await t.enterText(find.byType(TextField).at(1), '1234');
      await tap(t, find.textContaining('내 담당구역 보기'));
      await shot(t, 'staff_duty');
    });
  });
}
