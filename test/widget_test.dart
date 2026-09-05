// 화면이 "그려지기는 하는지"만 보는 최소 테스트.
// flutter analyze 는 Material(shape + borderRadius 동시 지정) 같은 런타임 assert 를
// 못 잡는다. 실제로 한 번 pump 해봐야 걸린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/screens/assign.dart';

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
}
