// 운영자 화면이 휴대폰·태블릿·데스크톱 세 크기에서 넘치지 않고 그려지는지 본다 (PLAN_RESPONSIVE.md §7).
// overflow 줄무늬는 analyze 가 못 잡고, 실제 크기로 pump 해야 걸린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/remote.dart';
import 'package:room_assignment/screens/gatherings.dart';
import 'package:room_assignment/theme.dart';
import 'package:room_assignment/widgets/room_board.dart';

import 'gathering_widget_test.dart'
    show FakeRemote, homestay, pendingReg, sample;

const phone = Size(390, 844),
    tablet = Size(820, 1180),
    desktop = Size(1440, 900);

void setView(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const Shell()),
  );
  await tester.pumpAndSettle();
}

/// 그리다 난 예외를 모두 모은다. takeException 은 하나만 돌려줘서 어느 탭인지 알기 어렵다.
List<String> drain(WidgetTester tester) {
  final out = <String>[];
  for (
    Object? e = tester.takeException();
    e != null;
    e = tester.takeException()
  ) {
    out.add(e.toString().split('\n').first);
  }
  return out;
}

void main() {
  setUp(() {
    tabIndex.value = 0;
    current.value = sample();
    remote = FakeRemote()
      ..gs.add(sample())
      ..regs.add(pendingReg());
    store.event = Event(
      name: '2026 가을 수련회',
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 3),
      rooms: [
        for (final no in ['301', '302', '303', '201', '202'])
          Room(id: 'r$no', roomNo: no, capacity: 4)
            // 홈스테이 가정의 입금 상태 표시도 같이 그려 본다.
            ..pay = no == '302' ? payPending : null,
      ],
      attendees: [
        for (var i = 0; i < 6; i++)
          Attendee(
            id: 'a$i',
            name: '참석자$i',
            gender: i.isEven ? 'M' : 'F',
            age: 20 + i,
            cell: '셀${i % 2}',
            zone: 'A존',
            checkIn: DateTime(2026, 10, 1),
            checkOut: DateTime(2026, 10, 3),
            roomId: i < 3 ? 'r301' : null,
          )
            // 방 타일·목록의 입금대기·신청 취소 표시가 좁은 폭에서 넘치지 않는지 본다.
            ..pay = switch (i) {
              1 || 4 => payPending,
              2 => payCancelled,
              _ => null,
            },
      ],
    );
  });

  for (final (name, size) in [
    ('휴대폰', phone),
    ('태블릿', tablet),
    ('데스크톱', desktop),
  ]) {
    for (final home in [false, true]) {
      testWidgets('$name${home ? ' 홈스테이' : ''}: 모든 탭이 넘치지 않고 그려진다', (
        tester,
      ) async {
        setView(tester, size);
        if (home) current.value = homestay();
        final failed = <String, List<String>>{};
        for (var i = 0; i <= dutyTasksTab; i++) {
          tabIndex.value = i;
          await pumpShell(tester);
          final errors = drain(tester);
          if (errors.isNotEmpty) failed[Shell.dest(i).$2] = errors;
        }
        expect(failed, isEmpty);
      });
    }
  }

  testWidgets('휴대폰: 메뉴는 햄버거 뒤에 있고, 고르면 탭이 바뀌고 메뉴가 닫힌다', (tester) async {
    setView(tester, phone);
    await pumpShell(tester);
    // 앱바 제목은 집회 이름 대신 지금 탭 이름.
    expect(find.widgetWithText(AppBar, '집회 설정'), findsOneWidget);
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('2026 가을 수련회'), findsOneWidget); // Drawer 머리
    await tester.tap(find.text('현황'));
    await tester.pumpAndSettle();
    expect(tabIndex.value, 6);
    expect(find.byType(Drawer), findsNothing);
    expect(find.widgetWithText(AppBar, '현황'), findsOneWidget);
  });

  testWidgets('태블릿: 메뉴는 아이콘 레일, 이름은 툴팁으로', (tester) async {
    setView(tester, tablet);
    await pumpShell(tester);
    expect(find.byTooltip('메뉴'), findsNothing);
    expect(find.byTooltip('방배정'), findsOneWidget);
    await tester.tap(find.byTooltip('방배정'));
    await tester.pumpAndSettle();
    expect(tabIndex.value, assignTab);
  });

  testWidgets('휴대폰 방배정: 사람 고르기 → 방 고르기 → 배정하면 처음 단계로 돌아온다', (tester) async {
    setView(tester, phone);
    boardAsList.value = true;
    tabIndex.value = assignTab;
    await pumpShell(tester);
    // 1단계: 보드는 아직 없다.
    expect(find.byType(RoomBoard), findsNothing);
    await tester.tap(find.text('참석자4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1명 · 방 고르기'));
    await tester.pumpAndSettle();
    // 2단계: 고른 사람 이름이 위에 남고, 보드는 목록 보기.
    expect(find.text('참석자4'), findsOneWidget);
    expect(find.text('목록'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final t = find.descendant(
      of: find.byType(RoomTile),
      matching: find.text('302'),
    );
    await tester.ensureVisible(t);
    await tester.tap(t);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('1명 → 1개 방 배정'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '배정'));
    await tester.pumpAndSettle();
    expect(
      store.event.attendees.firstWhere((a) => a.id == 'a4').roomId,
      'r302',
    );
    expect(find.byType(RoomBoard), findsNothing);
    expect(find.text('방 보기'), findsOneWidget); // 선택도 비웠다
  });

  testWidgets('휴대폰 보드: 격자로 바꿔 볼 수 있고, 자리 옮기기는 꺼져 있다', (tester) async {
    setView(tester, phone);
    boardAsList.value = true;
    addTearDown(() => boardAsList.value = true);
    tabIndex.value = assignTab;
    await pumpShell(tester);
    await tester.tap(find.text('방 보기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '자리 옮기기'))
          .onSelected,
      isNull,
    );
    await tester.tap(find.text('격자'));
    await tester.pumpAndSettle();
    expect(boardAsList.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [('휴대폰', phone), ('태블릿', tablet)]) {
    testWidgets('$name 신청·입금: 신청을 누르면 상세가 뜨고, 닫으면 목록으로 돌아온다', (tester) async {
      setView(tester, size);
      tabIndex.value = registrationsTab;
      await pumpShell(tester);
      expect(find.text('PIN 재설정'), findsNothing);
      await tester.tap(find.text('홍길동').first);
      await tester.pumpAndSettle();
      expect(find.text('PIN 재설정'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('PIN 재설정'), findsNothing);
      expect(find.text('홍길동'), findsWidgets);
    });
  }

  testWidgets('휴대폰 신청·입금: 나머지 버튼은 더보기 메뉴에 있다', (tester) async {
    setView(tester, phone);
    tabIndex.value = registrationsTab;
    await pumpShell(tester);
    expect(find.text('새로고침'), findsNothing);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    for (final t in ['새로고침', '신청 추가', '붙여넣기 추가', '은행 내역 올리기']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('휴대폰 자동배정: 안내와 [방배정으로]만 보인다', (tester) async {
    setView(tester, phone);
    tabIndex.value = 5;
    await pumpShell(tester);
    expect(find.textContaining('태블릿·PC'), findsOneWidget);
    await tester.tap(find.text('방배정으로'));
    await tester.pumpAndSettle();
    expect(tabIndex.value, assignTab);
  });

  testWidgets('태블릿 자동배정: 규칙 → 미리보기 → [취소]로 규칙에 돌아온다', (tester) async {
    setView(tester, const Size(820, 2000)); // 규칙 목록이 길어 [미리보기] 버튼까지 보이게
    tabIndex.value = 5;
    await pumpShell(tester);
    expect(find.text('규칙을 정하고 [미리보기]를 누르세요.'), findsNothing);
    await tester.tap(find.textContaining('미리보기 (미배정'));
    await tester.pumpAndSettle();
    expect(find.textContaining('미리보기 (미배정'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.textContaining('미리보기 (미배정'), findsOneWidget);
  });

  for (final (name, size) in [('휴대폰', phone), ('태블릿', tablet)]) {
    testWidgets('$name: 집회 목록이 넘치지 않고 그려진다', (tester) async {
      setView(tester, size);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const GatheringsScreen()),
      );
      await tester.pumpAndSettle();
      expect(drain(tester), isEmpty);
      expect(find.textContaining('가족수양회'), findsWidgets);
    });
  }

  testWidgets('홈스테이 표: 날짜를 옆으로 밀어도 이름은 남고, 세로 스크롤은 두 쪽이 같이 움직인다', (
    tester,
  ) async {
    setView(tester, phone);
    current.value = homestay();
    store.event = Event(
      name: '겨울 홈스테이',
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 20),
      attendees: [
        for (var i = 0; i < 40; i++)
          Attendee(
            id: 'k$i',
            name: '아이$i',
            gender: 'M',
            age: 10,
            checkIn: DateTime(2026, 10, 1),
            checkOut: DateTime(2026, 10, 20),
          ),
      ],
    );
    tabIndex.value = 3;
    await pumpShell(tester);
    final days = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    await tester.drag(days.last, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('아이0 ').hitTestable(), findsOneWidget);

    final lists = find.byWidgetPredicate(
      (w) => w is ListView && w.controller != null,
    );
    expect(lists, findsNWidgets(2));
    await tester.drag(lists.first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final offsets = [
      for (final e in lists.evaluate())
        (e.widget as ListView).controller!.offset,
    ];
    expect(offsets.first, greaterThan(0));
    expect(offsets.last, offsets.first);
  });

  for (final (name, size, full) in [
    ('휴대폰', phone, true),
    ('데스크톱', desktop, false),
  ]) {
    testWidgets('$name: 붙여넣기 등록은 ${full ? '전체 화면' : '다이얼로그'}로 열린다', (
      tester,
    ) async {
      setView(tester, size);
      tabIndex.value = 3;
      await pumpShell(tester);
      await tester.tap(find.text('붙여넣기 등록'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), full ? findsNothing : findsOneWidget);
      expect(find.byType(CloseButton), full ? findsOneWidget : findsNothing);
      await tester.tap(full ? find.byType(CloseButton) : find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('0명 저장'), findsNothing);
    });
  }
}
