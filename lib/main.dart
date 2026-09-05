import 'package:flutter/material.dart';

import 'auth.dart';
import 'models.dart';
import 'screens/assign.dart';
import 'screens/attendees.dart';
import 'screens/auto_assign_screen.dart';
import 'screens/rooms.dart';
import 'screens/status.dart';
import 'store.dart';
import 'theme.dart';

/// ponytail: 앱 상태는 전역 하나. 운영자 1명, 화면 5개. DI 컨테이너를 넣을 이유가 없다.
final store = Store();
final auth = Auth();

/// 탭 전환. 현황 화면에서 배정 화면으로 점프할 때도 이걸 쓴다.
final tabIndex = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  await auth.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '방배정',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: const Gate(),
    );
  }
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  /// const 인스턴스를 재사용하면 Flutter 가 "같은 위젯"이라 보고 rebuild 를 건너뛴다.
  /// store 가 바뀌어도 화면이 안 바뀌므로 매번 새로 만든다.
  static Widget _page(int i) => switch (i) {
    0 => RoomsScreen(),
    1 => AttendeesScreen(),
    2 => AssignScreen(),
    3 => AutoAssignScreen(),
    _ => StatusScreen(),
  };

  static const _dest = [
    (Icons.meeting_room_outlined, Icons.meeting_room, '방 관리'),
    (Icons.people_outline, Icons.people, '참석자'),
    (Icons.assignment_ind_outlined, Icons.assignment_ind, '방배정'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, '자동배정'),
    (Icons.dashboard_outlined, Icons.dashboard, '현황'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hotel,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(store.event.name),
            ],
          ),
          shape: const Border(bottom: BorderSide(color: AppColors.border)),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(
                '${fmtDate(store.event.startDate)} ~ ${fmtDate(store.event.endDate)}',
                style: const TextStyle(fontSize: 13),
              ),
              onPressed: () => _editEvent(context),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '비밀번호 변경',
              icon: const Icon(Icons.lock_outline, size: 20),
              onPressed: () => setPasswordDialog(context),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            if (store.loadError != null || store.saveError != null)
              _Warning(store.loadError ?? store.saveError!),
            Expanded(child: _rail(context)),
          ],
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    return Row(
      children: [
        ValueListenableBuilder(
          valueListenable: tabIndex,
          builder: (context, index, _) => NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => tabIndex.value = i,
            destinations: [
              for (final d in _dest)
                NavigationRailDestination(
                  icon: Icon(d.$1),
                  selectedIcon: Icon(d.$2),
                  label: Text(d.$3),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: tabIndex,
            builder: (context, index, _) => _page(index),
          ),
        ),
      ],
    );
  }

  Future<void> _editEvent(BuildContext context) async {
    final nameCtl = TextEditingController(text: store.event.name);
    var start = store.event.startDate;
    var end = store.event.endDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('집회 정보'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: '집회명'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('시작일'),
                  trailing: Text(fmtDate(start)),
                  onTap: () async {
                    final d = await pickDate(context, start);
                    if (d != null) setLocal(() => start = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('종료일'),
                  trailing: Text(fmtDate(end)),
                  onTap: () async {
                    final d = await pickDate(context, end);
                    if (d != null) setLocal(() => end = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    store.event.name = nameCtl.text.trim().isEmpty ? '집회' : nameCtl.text.trim();
    store.event.startDate = start;
    store.event.endDate = end.isAfter(start)
        ? end
        : start.add(const Duration(days: 1));
    store.commit();
  }
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<DateTime?> pickDate(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(initial.year - 2),
    lastDate: DateTime(initial.year + 3),
  );
  return d == null ? null : dateOnly(d);
}

/// 파일을 못 읽었거나 저장이 실패했을 때 띄우는 경고 줄.
class _Warning extends StatelessWidget {
  const _Warning(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFDECEC),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.warning_amber, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

/// 잠금 화면. 첫 실행이면 비밀번호를 정하고, 이후에는 확인만 한다.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  final pw = TextEditingController();
  String? error;
  bool unlocked = false;

  @override
  void dispose() {
    pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (unlocked) return const Shell();
    if (!auth.isSet) {
      return _SetPassword(onDone: () => setState(() => unlocked = true));
    }
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.hotel, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text(
                '방배정',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pw,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '관리자 비밀번호',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) => _try(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _try, child: const Text('열기')),
            ],
          ),
        ),
      ),
    );
  }

  void _try() {
    if (auth.check(pw.text)) {
      setState(() => unlocked = true);
    } else {
      setState(() => error = '비밀번호가 다릅니다');
    }
  }
}

class _SetPassword extends StatefulWidget {
  const _SetPassword({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_SetPassword> createState() => _SetPasswordState();
}

class _SetPasswordState extends State<_SetPassword> {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('관리자 비밀번호 설정', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '비밀번호',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: b,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '비밀번호 확인',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('설정')),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    if (a.text.length < 4) {
      setState(() => error = '4자 이상 입력하세요');
      return;
    }
    if (a.text != b.text) {
      setState(() => error = '두 입력이 다릅니다');
      return;
    }
    await auth.setPassword(a.text);
    widget.onDone();
  }
}

/// 앱바에서 비밀번호 변경. 기존 비밀번호 확인 후 새 비밀번호.
Future<void> setPasswordDialog(BuildContext context) async {
  final cur = TextEditingController();
  final next = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('비밀번호 변경'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cur,
              obscureText: true,
              decoration: const InputDecoration(labelText: '현재 비밀번호'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: '새 비밀번호 (4자 이상)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('변경'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  if (!auth.check(cur.text)) {
    messenger.showSnackBar(const SnackBar(content: Text('현재 비밀번호가 다릅니다')));
    return;
  }
  if (next.text.length < 4) {
    messenger.showSnackBar(const SnackBar(content: Text('새 비밀번호는 4자 이상')));
    return;
  }
  await auth.setPassword(next.text);
  messenger.showSnackBar(const SnackBar(content: Text('변경되었습니다')));
}
