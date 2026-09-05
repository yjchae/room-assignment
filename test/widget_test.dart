// 화면이 "그려지기는 하는지"만 보는 최소 테스트.
// flutter analyze 는 Material(shape + borderRadius 동시 지정) 같은 런타임 assert 를
// 못 잡는다. 실제로 한 번 pump 해봐야 걸린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/screens/assign.dart';
import 'package:room_assignment/screens/rooms.dart';
import 'package:room_assignment/screens/status.dart';
import 'package:room_assignment/theme.dart';

Room room(String no, int cap, {String? gender}) =>
    Room(id: 'r$no', roomNo: no, capacity: cap, gender: gender);

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  setUp(() {
    store.event = Event(
      name: 't',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 4),
      rooms: [room('301', 4), room('302', 2, gender: 'F')],
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

    await tester.tap(find.text('301'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1개 방 배정'), findsOneWidget);

    await tester.tap(find.text('302'));
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
        MaterialApp(theme: buildAppTheme(), home: Scaffold(body: screen)),
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
}
