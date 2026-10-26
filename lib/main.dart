import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'gathering.dart';
import 'models.dart';
import 'remote.dart';
import 'responsive.dart';
import 'screens/assign.dart';
import 'screens/attendees.dart';
import 'screens/duties.dart';
import 'screens/duty_tasks_screen.dart';
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

/// 열어 둔 집회의 설정을 고칠 수 있는가. false = 운영스탭 — [집회 설정] 메뉴를 막는다.
/// 막는 건 서버(room.configures)가 하고, 이건 못 쓰는 화면을 열지 않게 하는 것뿐이다.
final canConfigure = ValueNotifier<bool>(true);

/// 이 탭을 열 수 있는가. 운영스탭은 [집회 설정]을 못 연다 — 메뉴·앱바·탭 전환이 모두 이것만 본다.
bool canOpenTab(int i) => i != settingsTab || canConfigure.value;

/// 탭 전환. 현황 화면에서 배정 화면으로 점프할 때도 이걸 쓴다.
final tabIndex = ValueNotifier<int>(0);

/// 탭 번호. 다른 화면에서 탭을 넘길 때 숫자 대신 이걸 쓴다.
const settingsTab = 0,
    registrationsTab = 1,
    assignTab = 4,
    dutiesTab = 7,
    dutyTasksTab = 8;

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
      // 달력·기본 버튼 문구를 한국어로.
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // 휴대폰·태블릿이면 터치 영역·다이얼로그 여백을 넓힌다. 데스크톱은 그대로.
      builder: (context, child) => Theme(
        data: adaptTheme(
          Theme.of(context),
          touch: isTouchDevice,
          size: windowSizeOf(context),
        ),
        child: child!,
      ),
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
    dutiesTab => DutiesScreen(),
    dutyTasksTab => DutyTasksScreen(),
    _ => StatusScreen(),
  };

  static const _dest = [
    (Icons.tune_outlined, '집회 설정'),
    (Icons.receipt_long_outlined, '신청·입금'),
    (Icons.meeting_room_outlined, '방 관리'),
    (Icons.people_outline, '참석자'),
    (Icons.assignment_ind_outlined, '방배정'),
    (Icons.shuffle, '자동배정'),
    (Icons.space_dashboard_outlined, '현황'),
    (Icons.checklist_outlined, '담당구역'),
    (Icons.fact_check_outlined, '구역 할일'),
  ];

  /// 홈스테이는 방이 곧 가정이다. 메뉴 이름만 바꾸고 화면은 그대로 쓴다.
  static (IconData, String) dest(int i) {
    final (icon, label) = _dest[i];
    if (current.value?.isHomestay != true) return (icon, label);
    return (
      icon,
      switch (label) {
        '방 관리' => '가정 관리',
        '방배정' => '가정 배정',
        _ => label,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        store,
        current,
        signInCount,
        tabIndex,
        canConfigure,
      ]),
      builder: (context, _) {
        final size = windowSizeOf(context);
        final compact = size.isCompact;
        // 운영스탭은 [집회 설정]을 못 연다. 다른 곳에서 넘어와도 신청 화면을 보여 준다.
        final index = canOpenTab(tabIndex.value)
            ? tabIndex.value
            : registrationsTab;
        final dates =
            '${fmtDate(store.event.startDate)} ~ ${fmtDate(store.event.endDate)}';
        // 날짜·이름은 집회 설정(서버)에서 바꾼다. 여기서 바꾸면 신청 웹과 어긋난다.
        final openSettings = canOpenTab(settingsTab)
            ? () => tabIndex.value = settingsTab
            : null;
        return Scaffold(
          // 휴대폰: 메뉴는 햄버거 뒤 Drawer. 탭이 9개라 하단 NavigationBar(5개 권장)는 안 쓴다.
          drawer: compact
              ? Drawer(
                  width: 264,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(),
                  child: SafeArea(
                    child: _SideNav(
                      index,
                      width: null,
                      header: _DrawerHeader(dates: dates),
                      onPicked: () => Navigator.of(context).pop(),
                    ),
                  ),
                )
              : null,
          appBar: AppBar(
            // 휴대폰에서는 뒤로 가기 자리를 메뉴가 쓴다. 집회 목록으로 가는 길은 Drawer 머리에 있다.
            leading: compact
                ? Builder(
                    builder: (context) => IconButton(
                      tooltip: '메뉴',
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  )
                : null,
            titleSpacing: compact || Navigator.canPop(context) ? 0 : 20,
            // 휴대폰은 폭이 좁아 집회 이름 대신 지금 탭 이름을 적는다 (집회 이름은 Drawer 머리에).
            title: Text(
              compact ? dest(index).$2 : store.event.name,
              overflow: TextOverflow.ellipsis,
            ),
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
            actions: compact
                ? [
                    IconButton(
                      tooltip: dates,
                      icon: const Icon(
                        Icons.event_outlined,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      onPressed: openSettings,
                    ),
                    const BackupButton(iconOnly: true),
                    const AdminButton(iconOnly: true),
                    const SizedBox(width: 4),
                  ]
                : [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        dates,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFeatures: tabular,
                        ),
                      ),
                      onPressed: openSettings,
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
              Expanded(
                child: compact
                    ? _page(index)
                    : Row(
                        children: [
                          // 태블릿은 아이콘만 있는 레일, 데스크톱은 이름까지 있는 메뉴.
                          _SideNav(index, width: size.isExpanded ? 148 : 64),
                          const VerticalDivider(width: 1),
                          Expanded(child: _page(index)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 휴대폰 Drawer 맨 위: 집회 이름·기간과 집회 목록으로 돌아가는 길.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.dates});
  final String dates;

  @override
  Widget build(BuildContext context) {
    // Drawer 의 context 로 pop 하면 Drawer 만 닫힌다. 집회 목록은 그 아래 화면이다.
    final nav = Navigator.of(context);
    final fromList = ModalRoute.of(context)?.isFirst == false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.event.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dates,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontFeatures: tabular,
            ),
          ),
          if (fromList) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('집회 목록', style: TextStyle(fontSize: 13)),
              onPressed: () {
                nav.pop(); // Drawer
                nav.pop(); // 탭 화면
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 왼쪽 메뉴. 하는 순서대로 [준비 | 배정 | 스탭] 세 묶음.
/// 데스크톱은 폭 148(아이콘+이름), 태블릿은 폭 64 레일(아이콘만), 휴대폰은 Drawer 안(폭 null = 꽉 채움).
class _SideNav extends StatelessWidget {
  const _SideNav(this.index, {required this.width, this.header, this.onPicked});
  final int index;
  final double? width;

  /// Drawer 맨 위에 넣을 집회 이름 등.
  final Widget? header;

  /// 메뉴를 누른 뒤 할 일 (Drawer 닫기).
  final VoidCallback? onPicked;

  /// 숫자는 [Shell._dest] 의 탭 번호.
  static const _groups = [
    ('준비', [0, 1, 2, 3]),
    ('배정', [4, 5, 6]),
    ('스탭', [dutiesTab, dutyTasksTab]),
  ];

  bool get _rail => width != null && width! < 100;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    color: AppColors.surface,
    child: ListView(
      padding: EdgeInsets.fromLTRB(_rail ? 8 : 10, 4, _rail ? 8 : 10, 12),
      children: [
        ?header,
        for (final (i, (label, tabs)) in _groups.indexed) ...[
          // 레일은 묶음 이름이 들어갈 폭이 없어서 선으로만 나눈다.
          if (_rail)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: i == 0 ? const SizedBox(height: 1) : const Divider(),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textFaint,
                ),
              ),
            ),
          for (final t in tabs) _item(t),
        ],
      ],
    ),
  );

  Widget _item(int i) {
    final on = i == index;
    final (icon, label) = Shell.dest(i);
    // 운영스탭에게 [집회 설정]은 숨기지 않고 끈다 — 왜 못 여는지 툴팁으로 알린다.
    final locked = !canOpenTab(i);
    final glyph = Icon(
      icon,
      size: _rail ? 20 : 18,
      color: on
          ? AppColors.brand
          : locked
          ? AppColors.textFaint
          : AppColors.textMuted,
    );
    final item = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: on,
        label: _rail ? label : null,
        child: Material(
          color: on ? AppColors.bg : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: locked
                ? null
                : () {
                    tabIndex.value = i;
                    onPicked?.call();
                  },
            child: _rail
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: glyph),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        glyph,
                        const SizedBox(width: 10),
                        // 메뉴 폭이 고정이라 긴 이름은 자른다 (넘치면 RenderFlex 가 죽는다).
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: on
                                  ? AppColors.text
                                  : locked
                                  ? AppColors.textFaint
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
    if (locked) {
      return Tooltip(
        message: '$label은 집회관리자·보조운영자만 열 수 있습니다',
        preferBelow: false,
        child: item,
      );
    }
    // 레일은 이름이 안 보이니 마우스를 올리거나 길게 누르면 알려준다.
    return _rail
        ? Tooltip(message: label, preferBelow: false, child: item)
        : item;
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

/// 집회 기간 고르기. 달력에서 처음 누른 날이 시작일, 다음에 누른 날이 종료일이다
/// (범위가 잡힌 뒤 또 누르면 다시 시작일부터 — Flutter 기본 동작).
Future<DateTimeRange?> pickRange(
  BuildContext context,
  DateTime start,
  DateTime end,
) async {
  final r = await showDateRangePicker(
    context: context,
    initialDateRange: DateTimeRange(start: start, end: end),
    firstDate: DateTime(start.year - 2),
    lastDate: DateTime(start.year + 3),
    helpText: '집회 기간',
    saveText: '확인',
  );
  return r == null
      ? null
      : DateTimeRange(start: dateOnly(r.start), end: dateOnly(r.end));
}

/// 방배정을 못 불러왔거나 저장이 실패·충돌했을 때 띄우는 경고 줄.
class _Warning extends StatelessWidget {
  const _Warning(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.dangerSoft,
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
/// 비밀번호 재설정 메일 링크로 들어왔으면 새 비밀번호부터 정한다.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([signInCount, passwordRecovery]),
    builder: (context, _) {
      final reset = passwordRecovery.value && remote.signedIn;
      return remote.signedIn && !reset
          ? const GatheringsScreen()
          : Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '집회관리',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reset ? '새 비밀번호를 정하세요.' : '운영자 계정으로 로그인하세요.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (reset) ...[
                        PasswordForm(
                          askCurrent: false,
                          onDone: () {
                            passwordRecovery.value = false;
                            signInCount.value++;
                          },
                        ),
                      ] else
                        LoginForm(onDone: () => signInCount.value++),
                    ],
                  ),
                ),
              ),
            );
    },
  );
}

/// 앱바의 [백업]. 방배정(방·참석자·배정)을 JSON 파일로 내려받거나 파일로 되살린다.
/// 인터넷이 끊겨도 내려받기는 된다 — 지금 화면에 있는 그대로 저장한다.
class BackupButton extends StatelessWidget {
  const BackupButton({super.key, this.iconOnly = false});

  /// 휴대폰 앱바: 글자 없이 아이콘만.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '방배정 백업',
    onSelected: (v) => switch (v) {
      'csv' => _downloadCsv(context),
      'restore' => _restoreBackup(context),
      _ => _downloadBackup(context),
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'json', child: Text('JSON으로 내려받기')),
      PopupMenuItem(value: 'csv', child: Text('참석자 CSV로 내려받기 (엑셀)')),
      PopupMenuItem(value: 'restore', child: Text('JSON 파일로 되살리기')),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: iconOnly
          ? const Icon(
              Icons.save_alt_outlined,
              size: 20,
              color: AppColors.textMuted,
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.save_alt_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                SizedBox(width: 6),
                Text(
                  '백업',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
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
    // 웹은 바로 내려받고 저장 위치를 돌려주지 않는다(항상 null) — 그때도 안내한다.
    if (saved != null || kIsWeb) {
      messenger.showSnackBar(const SnackBar(content: Text('백업 파일을 저장했습니다.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('백업 파일을 저장하지 못했습니다. $e')));
  }
}

/// 참석자 목록(방·일정 포함)을 CSV 로 내려받는다. 되살리기는 JSON 으로만 된다.
/// 참석자 화면과 같은 목록을 적는다 — 당일(0박)만 오는 신청자는 참석자에 없어서
/// 신청을 같이 읽어야 한다 (하루짜리 집회는 참석자가 통째로 비어 있다).
Future<void> _downloadCsv(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = store.event.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final g = current.value;
  List<Registration>? regs;
  try {
    if (g != null && remote.signedIn) regs = await remote.registrations(g.id);
  } catch (_) {
    // 인터넷이 끊겨도 내려받기는 된다 — 그때는 방배정 참석자만 적는다.
  }
  try {
    final saved = await FilePicker.saveFile(
      fileName: '${name}_참석자_${ymd(DateTime.now())}.csv',
      // BOM 이 있어야 엑셀이 한글을 UTF-8 로 읽는다.
      bytes: utf8.encode(
        '﻿${attendeesCsv(store.event, g?.dateless == true ? store.event.attendees : store.everyone(g, regs), g?.dateless != true)}',
      ),
      mimeType: 'text/csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (saved != null || kIsWeb) {
      messenger.showSnackBar(const SnackBar(content: Text('CSV 파일을 저장했습니다.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('CSV 파일을 저장하지 못했습니다. $e')));
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
  final g = current.value;
  store.replaceEvent(e);
  if (g != null) store.applyGathering(g); // 이름·날짜는 집회 설정을 따른다
  messenger.showSnackBar(const SnackBar(content: Text('백업 파일로 되살렸습니다.')));
}
