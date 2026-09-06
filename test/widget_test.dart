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
    expect(find.text('에클레시아 2'), findsOneWidget); // 301호 타일
    expect(find.text('비어 있음'), findsWidgets); // 302호 타일
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
    expect(find.textContaining('선택한 방 인원'), findsNothing);
    expect(find.textContaining('김철수'), findsOneWidget); // 왼쪽 목록에만

    await tester.tap(find.text('301'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('선택한 방 인원 (1개 방)'), findsOneWidget);
    expect(find.textContaining('김철수'), findsNWidgets(2)); // 왼쪽 + 패널

    // 다시 누르면 선택 해제 -> 패널도 사라진다
    await tester.tap(find.text('301'));
    await tester.pumpAndSettle();
    expect(find.textContaining('선택한 방 인원'), findsNothing);
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
