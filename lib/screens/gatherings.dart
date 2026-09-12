import 'package:flutter/material.dart';

import '../gathering.dart';
import '../main.dart';
import '../models.dart';
import '../remote.dart';
import '../store.dart';
import '../theme.dart';

/// 운영자 로그인/로그아웃이 일어날 때마다 올라간다. 서버 탭들이 이걸 보고 다시 그린다.
final signInCount = ValueNotifier<int>(0);

/// 운영자로 로그인돼 있으면 true. 아니면 로그인 창을 띄운다.
Future<bool> ensureAdmin(BuildContext context) async {
  if (remote.signedIn) return true;
  final email = TextEditingController();
  final pw = TextEditingController();
  String? err;
  var busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        Future<void> go() async {
          setLocal(() {
            busy = true;
            err = null;
          });
          try {
            await remote.signIn(email.text, pw.text);
            if (context.mounted) Navigator.pop(context, true);
          } catch (e) {
            setLocal(() {
              busy = false;
              err = errorText(e);
            });
          }
        }

        return AlertDialog(
          title: const Text('운영자 로그인'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '집회 설정과 신청·입금 관리는 운영자 계정이 필요합니다. 한 번 로그인하면 이 PC에서 유지됩니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '이메일'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pw,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    errorText: err,
                    errorMaxLines: 3,
                  ),
                  onSubmitted: (_) => busy ? null : go(),
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
              onPressed: busy ? null : go,
              child: Text(busy ? '확인 중…' : '로그인'),
            ),
          ],
        );
      },
    ),
  );
  if (ok == true) signInCount.value++;
  return ok == true;
}

/// 앱바의 운영자 계정 버튼. 로그인 전엔 [운영자 로그인], 후엔 이메일 + 로그아웃 메뉴.
class AdminButton extends StatelessWidget {
  const AdminButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: signInCount,
    builder: (context, _, _) {
      final email = remote.adminEmail;
      if (email == null) {
        return TextButton.icon(
          icon: const Icon(Icons.login, size: 18),
          label: const Text('운영자 로그인', style: TextStyle(fontSize: 13)),
          onPressed: () => ensureAdmin(context),
        );
      }
      return PopupMenuButton<String>(
        tooltip: '운영자 계정',
        onSelected: (_) async {
          await remote.signOut();
          signInCount.value++;
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'out', child: Text('로그아웃')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: AppColors.brand,
              ),
              const SizedBox(width: 6),
              Text(email, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    },
  );
}

/// 집회 하나를 열어 탭 화면(Shell)으로 들어간다. [g] 가 null 이면 서버 없이 방배정만.
Future<void> openGathering(
  BuildContext context,
  String id,
  Gathering? g,
  Event fallback,
) async {
  await store.open(id, fallback);
  current.value = g;
  if (g != null) store.applyGathering(g);
  tabIndex.value = g == null ? assignTab : settingsTab;
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const Shell()));
  current.value = null;
}

/// 첫 화면: 집회 목록. 하나 고르면 그 집회의 탭 화면으로 들어간다.
class GatheringsScreen extends StatefulWidget {
  const GatheringsScreen({super.key});

  @override
  State<GatheringsScreen> createState() => _GatheringsScreenState();
}

class _GatheringsScreenState extends State<GatheringsScreen> {
  bool loading = true;

  /// 서버를 못 읽은 이유. null 이 아니면 이 PC 의 파일만 보여준다.
  String? error;
  List<Gathering> list = [];
  Map<String, ({int total, int confirmed})> counts = {};

  /// 이 PC 에 방배정 파일이 있는 집회.
  Map<String, Event> local = {};

  /// 집회 목록이 생기기 전 버전의 방배정 파일.
  Event? legacy;

  @override
  void initState() {
    super.initState();
    signInCount.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    signInCount.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    // 이 PC 의 파일은 따로 읽는다 — 서버 목록이 파일 읽기를 기다리지 않게.
    _loadLocal();
    try {
      list = await remote.gatherings();
      counts = remote.signedIn ? await remote.registrationCounts() : {};
    } catch (e) {
      error = errorText(e);
      list = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadLocal() async {
    try {
      final l = await Store.localEvents();
      final old = await Store.legacyEvent();
      if (mounted) {
        setState(() {
          local = l;
          legacy = old;
        });
      }
    } catch (_) {
      // 파일 폴더를 못 읽는 환경. 서버 목록만 보여준다.
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(String id, Gathering? g, [Event? localEvent]) async {
    final fallback = Event(
      name: g?.name ?? localEvent?.name ?? '집회',
      startDate: dateOnly(g?.start ?? localEvent?.startDate ?? DateTime.now()),
      endDate: dateOnly(g?.end ?? localEvent?.endDate ?? DateTime.now()),
      customFields: [...?g?.formFields],
    );
    await openGathering(context, id, g, fallback);
    if (mounted) _load();
  }

  Future<void> _create() async {
    if (!await ensureAdmin(context) || !mounted) return;
    final name = TextEditingController();
    var start = dateOnly(DateTime.now()).add(const Duration(days: 30));
    var end = start.add(const Duration(days: 2));
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('새 집회'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '집회 이름 *',
                    hintText: '예: 신촌하나교회 가족수양회',
                    errorText: err,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('시작일'),
                  trailing: Text('${start.year}-${mdw(start)}'),
                  onTap: () async {
                    final d = await pickDate(context, start);
                    if (d == null) return;
                    setLocal(() {
                      start = d;
                      if (end.isBefore(start)) end = start;
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('종료일'),
                  trailing: Text('${end.year}-${mdw(end)}'),
                  onTap: () async {
                    final d = await pickDate(context, end);
                    if (d != null && !d.isBefore(start)) {
                      setLocal(() => end = d);
                    }
                  },
                ),
                const Text(
                  '장소·회비·계좌 등은 만든 뒤 [집회 설정]에서 입력합니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setLocal(() => err = '이름을 입력하세요');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final g = await remote.saveGathering(
        Gathering(name: name.text.trim(), start: start, end: end),
      );
      if (mounted) await _open(g.id, g);
    } catch (e) {
      _snack(errorText(e));
    }
  }

  Future<void> _adoptLegacy() async {
    final e = legacy!;
    if (!await ensureAdmin(context)) return;
    try {
      final g = await remote.saveGathering(
        Gathering(
          name: e.name,
          start: e.startDate,
          end: e.endDate,
          formFields: [...e.customFields],
        ),
      );
      await Store.adoptLegacy(g.id);
      await _load();
      _snack('기존 방배정 데이터를 "${g.name}" 집회로 옮겼습니다.');
    } catch (err) {
      _snack(errorText(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = error != null;
    final serverIds = {for (final g in list) g.id};
    final localOnly = [
      for (final e in local.entries)
        if (!serverIds.contains(e.key)) e,
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('집회 목록'),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const AdminButton(),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: offline || loading ? null : _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('새 집회'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (offline)
                  _Banner(
                    icon: Icons.cloud_off_outlined,
                    text:
                        '$error\n이 PC에 저장된 집회만 보여줍니다. 방배정은 계속 할 수 있고, '
                        '집회 설정·신청 관리는 연결된 뒤에 됩니다.',
                  ),
                if (legacy != null)
                  _Banner(
                    icon: Icons.inventory_2_outlined,
                    text:
                        '이전 버전의 방배정 데이터가 있습니다: ${legacy!.name} '
                        '(${ymd(legacy!.startDate)} ~ ${ymd(legacy!.endDate)}, '
                        '참석자 ${legacy!.attendees.length}명)',
                    action: FilledButton(
                      onPressed: offline ? null : _adoptLegacy,
                      child: const Text('집회로 등록'),
                    ),
                  ),
                if (list.isEmpty && localOnly.isEmpty)
                  EmptyNotice(
                    icon: Icons.event_note_outlined,
                    text: offline
                        ? '이 PC에 저장된 집회가 없습니다.'
                        : '아직 집회가 없습니다. [새 집회]로 시작하세요.',
                  ),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final g in list)
                      _GatheringCard(
                        name: g.name,
                        dates:
                            '${g.start.year}-${mdw(g.start)} ~ ${mdw(g.end)} · ${stayLabel(g.nights)}',
                        place: g.place,
                        imageUrl: g.backgroundUrl,
                        badges: [
                          g.acceptingOn(DateTime.now())
                              ? const _Badge('신청 받는 중', AppColors.ok)
                              : const _Badge('신청 닫힘', AppColors.textMuted),
                          if (counts[g.id] case final c?)
                            _Badge(
                              '신청 ${c.total} · 확정 ${c.confirmed}',
                              AppColors.brand,
                            ),
                        ],
                        onTap: () => _open(g.id, g),
                      ),
                    for (final e in localOnly)
                      _GatheringCard(
                        name: e.value.name,
                        dates:
                            '${ymd(e.value.startDate)} ~ ${ymd(e.value.endDate)}',
                        badges: const [_Badge('이 PC 파일만', AppColors.textMuted)],
                        onTap: () => _open(e.key, null, e.value),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _GatheringCard extends StatelessWidget {
  const _GatheringCard({
    required this.name,
    required this.dates,
    required this.badges,
    required this.onTap,
    this.place,
    this.imageUrl,
  });
  final String name, dates;
  final String? place, imageUrl;
  final List<Widget> badges;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 110,
              child: imageUrl == null
                  ? const ColoredBox(
                      color: AppColors.brandSoft,
                      child: Icon(
                        Icons.church_outlined,
                        size: 36,
                        color: AppColors.brand,
                      ),
                    )
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppColors.brandSoft),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dates,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if ((place ?? '').isNotEmpty)
                    Text(
                      place!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
