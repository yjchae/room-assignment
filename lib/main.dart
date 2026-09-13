import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'gathering.dart';
import 'models.dart';
import 'remote.dart';
import 'screens/assign.dart';
import 'screens/attendees.dart';
import 'screens/auto_assign_screen.dart';
import 'screens/gathering_settings.dart';
import 'screens/gatherings.dart';
import 'screens/registrations.dart';
import 'screens/rooms.dart';
import 'screens/status.dart';
import 'store.dart';
import 'theme.dart';

/// ponytail: 앱 상태는 전역 하나. 운영자 1명, 화면 몇 개. DI 컨테이너를 넣을 이유가 없다.
final store = Store();

/// 지금 열어 둔 집회의 서버 설정. 집회를 열지 않았으면 null.
final current = ValueNotifier<Gathering?>(null);

/// 탭 전환. 현황 화면에서 배정 화면으로 점프할 때도 이걸 쓴다.
final tabIndex = ValueNotifier<int>(0);

/// 탭 번호. 다른 화면에서 탭을 넘길 때 숫자 대신 이걸 쓴다.
const settingsTab = 0, registrationsTab = 1, assignTab = 4;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 서버 준비. 실패해도 앱은 열린다 — 로그인할 때 연결 문제를 알려준다.
  try {
    await Remote.init();
  } catch (e) {
    debugPrint('서버 준비 실패: $e');
  }
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '집회관리',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: const Gate(),
    );
  }
}

/// 집회 하나의 탭 화면. 집회 목록에서 들어온다.
class Shell extends StatelessWidget {
  const Shell({super.key});

  /// const 인스턴스를 재사용하면 Flutter 가 "같은 위젯"이라 보고 rebuild 를 건너뛴다.
  /// store 가 바뀌어도 화면이 안 바뀌므로 매번 새로 만든다.
  static Widget _page(int i) => switch (i) {
    settingsTab => GatheringSettingsScreen(),
    registrationsTab => RegistrationsScreen(),
    2 => RoomsScreen(),
    3 => AttendeesScreen(),
    assignTab => AssignScreen(),
    5 => AutoAssignScreen(),
    _ => StatusScreen(),
  };

  static const _dest = [
    (Icons.tune_outlined, Icons.tune, '집회 설정'),
    (Icons.receipt_long_outlined, Icons.receipt_long, '신청·입금'),
    (Icons.meeting_room_outlined, Icons.meeting_room, '방 관리'),
    (Icons.people_outline, Icons.people, '참석자'),
    (Icons.assignment_ind_outlined, Icons.assignment_ind, '방배정'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, '자동배정'),
    (Icons.dashboard_outlined, Icons.dashboard, '현황'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, current, signInCount]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: Navigator.canPop(context) ? 0 : 20,
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hotel, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(store.event.name, overflow: TextOverflow.ellipsis),
              ),
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
              // 날짜·이름은 집회 설정(서버)에서 바꾼다. 여기서 바꾸면 신청 웹과 어긋난다.
              onPressed: () => tabIndex.value = settingsTab,
            ),
            const SizedBox(width: 4),
            const BackupButton(),
            const SizedBox(width: 4),
            const AdminButton(),
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

/// 방배정을 못 불러왔거나 저장이 실패·충돌했을 때 띄우는 경고 줄.
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

/// 첫 화면. 운영자로 로그인돼 있으면 집회 목록, 아니면 로그인.
/// 로그인은 이 기기(앱·브라우저)에 남아서 다음부터는 바로 목록이 뜬다.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: signInCount,
    builder: (context, _, _) => remote.signedIn
        ? const GatheringsScreen()
        : Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.hotel, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '집회관리',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LoginForm(onDone: () => signInCount.value++),
                  ],
                ),
              ),
            ),
          ),
  );
}

/// 앱바의 [백업]. 방배정(방·참석자·배정)을 JSON 파일로 내려받거나 파일로 되살린다.
/// 인터넷이 끊겨도 내려받기는 된다 — 지금 화면에 있는 그대로 저장한다.
class BackupButton extends StatelessWidget {
  const BackupButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    tooltip: '방배정 백업',
    onSelected: (restore) =>
        restore ? _restoreBackup(context) : _downloadBackup(context),
    itemBuilder: (_) => const [
      PopupMenuItem(value: false, child: Text('JSON으로 내려받기')),
      PopupMenuItem(value: true, child: Text('JSON 파일로 되살리기')),
    ],
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.save_alt_outlined, size: 18, color: AppColors.brand),
          SizedBox(width: 6),
          Text('백업', style: TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );
}

Future<void> _downloadBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = store.event.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  try {
    final saved = await FilePicker.saveFile(
      fileName: '${name}_방배정_${ymd(DateTime.now())}.json',
      bytes: utf8.encode(
        const JsonEncoder.withIndent('  ').convert(store.event.toJson()),
      ),
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (saved != null) {
      messenger.showSnackBar(const SnackBar(content: Text('백업 파일을 저장했습니다.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('백업 파일을 저장하지 못했습니다. $e')));
  }
}

/// 백업 파일로 방배정을 통째로 바꾼다. 예전 버전 PC 의 방배정 파일(`events/<id>.json`)도
/// 같은 모양이라 그대로 읽힌다.
Future<void> _restoreBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (file == null || !context.mounted) return;
  final Event e;
  try {
    e = Event.fromJson(
      jsonDecode(utf8.decode(await file.readAsBytes())) as Map<String, dynamic>,
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('방배정 백업 파일이 아닙니다. 내려받은 JSON 파일을 고르세요.')),
    );
    return;
  }
  if (!context.mounted) return;
  final now = store.event;
  final ok = await confirmDialog(
    context,
    title: '백업 파일로 되살리기',
    body:
        '지금 방배정(방 ${now.rooms.length}개 · 참석자 ${now.attendees.length}명)을 '
        '파일 내용(방 ${e.rooms.length}개 · 참석자 ${e.attendees.length}명)으로 바꿉니다. '
        '다른 기기에도 바로 반영되고 되돌릴 수 없습니다.',
    action: '되살리기',
    danger: true,
  );
  if (!ok) return;
  store.event = e;
  final g = current.value;
  if (g != null) store.applyGathering(g); // 이름·날짜는 집회 설정을 따른다
  store.commit();
  messenger.showSnackBar(const SnackBar(content: Text('백업 파일로 되살렸습니다.')));
}
