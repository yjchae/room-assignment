// 화면이 "그려지기는 하는지"만 보는 최소 테스트.
// flutter analyze 는 Material(shape + borderRadius 동시 지정) 같은 런타임 assert 를
// 못 잡는다. 실제로 한 번 pump 해봐야 걸린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/screens/assign.dart';
import 'package:room_assignment/screens/auto_assign_screen.dart';
import 'package:room_assignment/screens/rooms.dart';
import 'package:room_assignment/screens/status.dart';
import 'package:room_assignment/theme.dart';

Room room(String no, int cap, {String? gender}) =>
    Room(id: 'r$no', roomNo: no, capacity: cap, gender: gender);

/// 방 타일의 호수 글자. 왼쪽 참석자 목록에도 배정된 호수 배지가 있어
/// find.text 만 쓰면 대상이 모호해진다.
Finder tile(String roomNo) =>
    find.descendant(of: find.byType(RoomTile), matching: find.text(roomNo));

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  // 이 앱은 데스크톱 전용이다. 기본 테스트 화면(800x600)은 실제 창보다 훨씬 좁아
  // 방 타일이 화면 밖으로 밀려 탭이 빗나간다.
  setUpAll(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(2800, 1800);
    view.devicePixelRatio = 2.0;
  });

  setUp(() {
    store.event = Event(
      name: 't',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 4),
      rooms: [
        room('301', 4),
        room('302', 2, gender: 'F'),
      ],
      attendees: [],
    );
  });

  testWidgets('RoomTile 은 선택/비선택 both 렌더된다', (tester) async {
    for (final selected in [false, true]) {
      await pump(
        tester,
        RoomTile(room: store.event.rooms.first, selected: selected),
      );
      expect(tester.takeException(), isNull, reason: 'selected=$selected');
    }
  });

  testWidgets('방배정 화면이 뜬다', (tester) async {
    // AssignScreen 은 자체 Scaffold 가 없다 (실제로는 Shell 의 Scaffold 안에 들어간다).
    await pump(tester, const AssignScreen());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('301'), findsOneWidget);
    expect(find.textContaining('개 방 배정'), findsOneWidget);
  });

  testWidgets('방 타일에 들어있는 그룹이 표시된다', (tester) async {
    store.event.attendees.addAll([
      for (var i = 0; i < 2; i++)
        Attendee(
          id: 'e$i',
          name: '에클$i',
          gender: 'M',
          age: 30,
          cell: '에클레시아',
          roomId: 'r301',
          checkIn: DateTime(2026, 1, 1),
          checkOut: DateTime(2026, 1, 4),
        ),
    ]);
    await pump(tester, const AssignScreen());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 타일은 66px 고정이라 그룹 이름은 툴팁으로 보여준다.
    final tips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .toList();
    expect(tips.any((m) => m.contains('에클레시아 2')), isTrue, reason: '$tips');
    expect(tips.any((m) => m.contains('비어 있음')), isTrue, reason: '$tips');
  });

  testWidgets('방을 클릭하면 그 방 인원이 아래 패널에 뜬다', (tester) async {
    store.event.attendees.add(
      Attendee(
        id: 'x1',
        name: '김철수',
        gender: 'M',
        age: 41,
        cell: '1셀',
        roomId: 'r301',
        checkIn: DateTime(2026, 1, 1),
        checkOut: DateTime(2026, 1, 4),
      ),
    );
    await pump(tester, const AssignScreen());
    await tester.pumpAndSettle();

    // 왼쪽 참석자 목록에도 이름이 있으므로 패널 유무로 판단한다.
    expect(find.textContaining('고른 방 인원'), findsNothing);
    expect(find.textContaining('김철수'), findsOneWidget); // 왼쪽 목록에만

    await tester.tap(tile('301'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('고른 방 인원 (1개 방)'), findsOneWidget);
    expect(find.textContaining('김철수'), findsNWidgets(2)); // 왼쪽 + 패널

    // 다시 누르면 선택 해제 -> 패널도 사라진다
    await tester.tap(tile('301'));
    await tester.pumpAndSettle();
    expect(find.textContaining('고른 방 인원'), findsNothing);
  });

  testWidgets('방을 누르면 선택되고 배정 버튼 라벨이 바뀐다', (tester) async {
    store.event.attendees.add(
      Attendee(
        id: 'a1',
        name: '홍길동',
        gender: 'M',
        age: 30,
        checkIn: DateTime(2026, 1, 1),
        checkOut: DateTime(2026, 1, 4),
      ),
    );
    await pump(tester, const AssignScreen());
    await tester.pumpAndSettle();

    await tester.tap(tile('301'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1개 방 배정'), findsOneWidget);

    await tester.tap(tile('302'));
    await tester.pump();
    expect(find.textContaining('2개 방 배정'), findsOneWidget);
  });

  testWidgets('보드는 한 줄에 10칸까지만 채운다', (tester) async {
    store.event.rooms
      ..clear()
      ..addAll([for (var i = 1; i <= 12; i++) room('${300 + i}', 4)]);

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, RoomBoard(rooms: store.event.rooms));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final tiles = find.byType(RoomTile);
    expect(tiles, findsNWidgets(12));
    final firstRowY = tester.getTopLeft(tiles.at(0)).dy;
    // 1~10번째는 같은 줄, 11번째부터 다음 줄.
    for (var i = 1; i < 10; i++) {
      expect(tester.getTopLeft(tiles.at(i)).dy, firstRowY, reason: '$i번째');
    }
    expect(tester.getTopLeft(tiles.at(10)).dy, greaterThan(firstRowY));
  });

  testWidgets('층은 높은 층이 위로 온다', (tester) async {
    store.event.rooms
      ..clear()
      ..addAll([room('201', 4), room('401', 4), room('301', 4)]);
    await pump(tester, RoomBoard(rooms: store.event.rooms));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('401')).dy,
      lessThan(tester.getTopLeft(find.text('301')).dy),
    );
    expect(
      tester.getTopLeft(find.text('301')).dy,
      lessThan(tester.getTopLeft(find.text('201')).dy),
    );
  });

  testWidgets('현황/방관리 화면이 뜬다', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final screen in [const StatusScreen(), const RoomsScreen()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: screen),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$screen');
    }
  });

  test('방 상태 판정', () {
    expect(statusOf(used: 0, capacity: 4), RoomStatus.empty);
    expect(statusOf(used: 1, capacity: 4), RoomStatus.partial);
    expect(statusOf(used: 4, capacity: 4), RoomStatus.full);
    expect(statusOf(used: 5, capacity: 4), RoomStatus.over);
  });

  testWidgets('자동배정: 기준 순서를 바꾸면 순위 표시가 따라간다', (tester) async {
    await pump(tester, const AutoAssignScreen());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 기본값: 존 1순위, 셀 2순위
    expect(find.text('현재 순서: 존 → 셀'), findsOneWidget);
    expect(find.text('1순위'), findsOneWidget);

    // 셀 체크를 끄면 존만 남는다
    final cellTile = find.ancestor(
      of: find.text('셀'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: cellTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('현재 순서: 존'), findsOneWidget);
  });

  testWidgets('자동배정: 사용자 정의 항목이 기준 목록에 나타난다', (tester) async {
    store.event.customFields.add('교회');
    await pump(tester, const AutoAssignScreen());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 기본 3개 + 교회
    expect(find.text('교회'), findsOneWidget);
    expect(find.text('현재 순서: 존 → 셀'), findsOneWidget);

    final churchTile = find.ancestor(
      of: find.text('교회'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: churchTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('현재 순서: 존 → 셀 → 교회'), findsOneWidget);
  });

  testWidgets('앱바에 비밀번호 변경 버튼이 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Shell()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('비밀번호'), findsOneWidget);
  });

  testWidgets('비밀번호 변경 다이얼로그가 뜬다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Shell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('비밀번호'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('비밀번호 변경'), findsOneWidget);
    expect(find.text('현재 비밀번호'), findsOneWidget);
    expect(find.textContaining('새 비밀번호'), findsWidgets);
  });
}
