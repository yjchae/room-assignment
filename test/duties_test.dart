// 스탭 신청 항목과 담당구역. 모델·저장 규칙을 먼저 보고, 화면은 한 번 그려 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';
import 'package:room_assignment/main.dart';
import 'package:room_assignment/models.dart';
import 'package:room_assignment/screens/duties.dart';
import 'package:room_assignment/screens/duty_tasks_screen.dart';
import 'package:room_assignment/widgets/duty_tasks.dart';
import 'package:room_assignment/store.dart';
import 'package:room_assignment/screens/gathering_settings.dart' show setFieldMode;
import 'package:room_assignment/theme.dart';

final start = DateTime(2026, 1, 1);
final end = DateTime(2026, 1, 4);

Gathering g() => Gathering(id: 'g1', name: '테스트 집회', start: start, end: end);

Attendee person(String id, {bool staff = false}) => Attendee(
  id: id,
  name: id,
  gender: 'M',
  age: 30,
  checkIn: start,
  checkOut: end,
)..staff = staff;

void main() {
  group('스탭 신청 항목', () {
    test('기본은 안 받음 — 켠 집회에서만 신청서에 나온다', () {
      final x = g();
      expect(x.asks('staff'), isFalse);
      expect(x.asks('cell'), isTrue); // 보통 항목은 예전처럼 기본 '선택'

      setFieldMode(x, 'staff', 'optional');
      expect(x.asks('staff'), isTrue);
      expect(x.requires('staff'), isFalse);

      setFieldMode(x, 'staff', 'required');
      expect(x.requires('staff'), isTrue);

      setFieldMode(x, 'staff', 'off');
      expect(x.asks('staff'), isFalse);
      expect(x.requires('staff'), isFalse);
      expect(x.hiddenFields, isNot(contains('staff'))); // 켠 목록으로만 관리한다
    });

    test('보통 항목은 뺀 목록으로 관리한다', () {
      final x = g();
      setFieldMode(x, 'gender', 'off');
      expect(x.hiddenFields, contains('gender'));
      expect(x.asks('gender'), isFalse);
      setFieldMode(x, 'gender', 'required');
      expect(x.requires('gender'), isTrue);
    });

    test('서버 칸으로 오갔다 와도 그대로다', () {
      final x = g();
      setFieldMode(x, 'staff', 'required');
      final back = Gathering.fromRow({...x.toRow(), 'id': x.id});
      expect(back.asks('staff'), isTrue);
      expect(back.requires('staff'), isTrue);
    });

    test('신청자의 스탭 체크가 참석자까지 따라온다', () {
      final x = g()..fee = FeeRule();
      setFieldMode(x, 'staff', 'optional');
      final p = Person(
        id: 'p1',
        name: '김스탭',
        gender: 'M',
        birthYear: 1990,
        staff: true,
      );
      expect(Person.fromJson(p.toJson()).staff, isTrue);

      final r = Registration(
        id: 'r1',
        gatheringId: x.id,
        phone: '01012345678',
        people: [p],
        status: RegStatus.confirmed,
        createdAt: start,
      );
      final s = Store()..event = Event(name: '', startDate: start, endDate: end);
      s.syncRegistrations(x, [r]);
      expect(s.event.attendees.single.staff, isTrue);
      // 저장했다 읽어도 남는다.
      final back = Event.fromJson(s.event.toJson());
      expect(back.attendees.single.staff, isTrue);
    });
  });

  group('담당구역', () {
    late Store s;
    setUp(() {
      s = Store()
        ..event = Event(
          name: '테스트',
          startDate: start,
          endDate: end,
          attendees: [person('가', staff: true), person('나'), person('다')],
        );
    });

    test('구역을 만들고 사람을 배정한다 (한 사람이 여러 구역)', () {
      final kitchen = Duty(id: 'd1', name: '주방', capacity: 2, tasks: '배식');
      final car = Duty(id: 'd2', name: '차량');
      s
        ..addDuty(kitchen)
        ..addDuty(car)
        ..setDutyMembers(kitchen, ['가', '나'])
        ..setDutyMembers(car, ['가']);

      expect(s.membersOf(kitchen).map((a) => a.name), ['가', '나']);
      expect(s.dutiesOf(person('가')).map((d) => d.name), ['주방', '차량']);
      expect(s.dutiesOf(person('다')), isEmpty);
    });

    test('같은 사람을 두 번 넣어도 한 번만 들어간다', () {
      final d = Duty(id: 'd1', name: '주방');
      s
        ..addDuty(d)
        ..setDutyMembers(d, ['가', '가', '나']);
      expect(d.personIds.length, 2);
    });

    test('참석자를 지우면 구역에서도 빠진다', () {
      final d = Duty(id: 'd1', name: '주방');
      s
        ..addDuty(d)
        ..setDutyMembers(d, ['가', '나']);
      s.deleteAttendees([s.event.attendees.firstWhere((a) => a.name == '가')]);
      expect(d.personIds, ['나']);
    });

    test('기간을 나눈 조각을 지워도 사람이 남아 있으면 배정은 그대로다', () {
      final d = Duty(id: 'd1', name: '주방');
      s
        ..addDuty(d)
        ..setDutyMembers(d, ['가']);
      final later = s.splitStay(
        s.event.attendees.firstWhere((a) => a.name == '가'),
        DateTime(2026, 1, 2),
      );
      expect(later, isNotNull);
      expect(s.membersOf(d).length, 1); // 화면에는 한 줄
      s.deleteAttendees([later!]);
      expect(d.personIds, ['가']);
    });

    test('구역을 지우면 배정도 사라진다. 문서에 저장됐다 그대로 읽힌다', () {
      final d = Duty(id: 'd1', name: '주방', capacity: 3, tasks: '배식\n뒷정리');
      s
        ..addDuty(d)
        ..setDutyMembers(d, ['가']);
      final back = Event.fromJson(s.event.toJson());
      expect(back.duties.single.name, '주방');
      expect(back.duties.single.capacity, 3);
      expect(back.duties.single.tasks, '배식\n뒷정리');
      expect(back.duties.single.personIds, ['가']);

      s.deleteDuty(d);
      expect(s.event.duties, isEmpty);
    });
  });

  group('담당구역 화면', () {
    setUp(() {
      current.value = null;
      store.event = Event(
        name: '테스트',
        startDate: start,
        endDate: end,
        attendees: [person('가', staff: true), person('나')],
      );
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          // 앱에서는 Shell 의 Scaffold 안에서 살고, Shell 이 store 를 듣고 다시 그린다.
          home: Scaffold(
            body: ListenableBuilder(
              listenable: store,
              // const 로 만들면 Flutter 가 같은 위젯이라 보고 다시 그리지 않는다 (Shell 도 같다).
              builder: (_, _) => DutiesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('구역이 없으면 만들라고 안내한다', (tester) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('담당구역이 없습니다'), findsOneWidget);
    });

    testWidgets('구역을 만들고 참석자를 배정한다', (tester) async {
      await pump(tester);
      // 빈 화면에는 [구역 추가]가 위 카드와 안내 두 곳에 있다.
      await tester.tap(find.widgetWithText(FilledButton, '구역 추가').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '구역 이름'), '주방');
      await tester.enterText(find.widgetWithText(TextField, '해야 할 일'), '배식');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(store.event.duties.single.name, '주방');
      expect(store.event.duties.single.tasks, '배식');
      expect(find.text('배식'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, '인원 배정'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '스탭만'));
      await tester.pumpAndSettle();
      expect(find.textContaining('나'), findsNothing); // 스탭만 남는다
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '배정'));
      await tester.pumpAndSettle();
      expect(store.event.duties.single.personIds, ['가']);
      expect(tester.takeException(), isNull);
    });
  });

  group('담당구역 할 일 표', () {
    test('행을 더하고 지우고, 문서에 저장됐다 그대로 읽힌다', () {
      final s = Store()
        ..event = Event(name: '테스트', startDate: start, endDate: end);
      final d = Duty(id: 'd1', name: '주방');
      s.addDuty(d);
      d.items.addAll([
        DutyTask(id: 't1', kind: '준비물', content: '국자', qty: '2', done: true),
        DutyTask(id: 't2', kind: '예산', content: '장보기', qty: '10만원'),
      ]);
      s.commit();
      expect(d.doneCount, 1);

      final back = Event.fromJson(s.event.toJson()).duties.single;
      expect(back.items.map((t) => t.content), ['국자', '장보기']);
      expect(back.items.first.done, isTrue);
      expect(back.items.last.done, isFalse);
      expect(back.items.last.qty, '10만원');
    });

    testWidgets('+ 행 추가로 줄을 늘리고 체크하면 바로 반영된다', (tester) async {
      final items = <DutyTask>[];
      var changed = 0;
      var n = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DutyTaskTable(
              items: items,
              newId: () => 't${n++}',
              onChanged: () => changed++,
            ),
          ),
        ),
      );
      expect(find.text('적어 둔 할 일이 없습니다.'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '행 추가'));
      await tester.pumpAndSettle();
      expect(items.length, 1);

      await tester.enterText(find.widgetWithText(TextField, '내용'), '국자 2개');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect((items.single.content, items.single.done), ('국자 2개', true));
      expect(changed, greaterThan(1));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(items, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('운영자 화면은 모든 구역의 할 일을 모아 보여준다', (tester) async {
      current.value = null;
      store.event = Event(
        name: '테스트',
        startDate: start,
        endDate: end,
        attendees: [person('가', staff: true)],
        duties: [
          Duty(
            id: 'd1',
            name: '주방',
            personIds: ['가'],
            items: [DutyTask(id: 't1', content: '국자', done: true)],
          ),
          Duty(id: 'd2', name: '차량'),
        ],
      );
      tester.view.physicalSize = const Size(1400, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: store,
              builder: (_, _) => DutyTasksScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('구역 2개 · 할 일 1개 · 완료 1개'), findsOneWidget);
      expect(find.text('주방'), findsOneWidget);
      expect(find.text('차량'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('0/0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
