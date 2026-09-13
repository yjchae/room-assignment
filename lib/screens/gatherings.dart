import 'package:flutter/material.dart';

import '../gathering.dart';
import '../main.dart';
import '../models.dart';
import '../remote.dart';
import '../theme.dart';

/// 운영자 로그인/로그아웃이 일어날 때마다 올라간다. 서버 탭들이 이걸 보고 다시 그린다.
final signInCount = ValueNotifier<int>(0);

/// 운영자로 로그인돼 있으면 true. 아니면(로그인이 풀렸으면) 로그인 창을 띄운다.
Future<bool> ensureAdmin(BuildContext context) async {
  if (remote.signedIn) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('운영자 로그인'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '로그인이 풀렸습니다. 다시 로그인하세요.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            LoginForm(onDone: () => Navigator.pop(context, true)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
      ],
    ),
  );
  if (ok == true) signInCount.value++;
  return ok == true;
}

/// 운영자 이메일·비밀번호 입력. 로그인되면 [onDone]. 첫 화면과 로그인 창이 같이 쓴다.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final email = TextEditingController();
  final pw = TextEditingController();
  String? err;
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (busy) return;
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await remote.signIn(email.text, pw.text);
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          err = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: '이메일'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: pw,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: '비밀번호',
            errorText: err,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : _go,
          child: Text(busy ? '확인 중…' : '로그인'),
        ),
      ],
    ),
  );
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
          // 집회 탭 화면에서 로그아웃해도 첫 화면(로그인)으로 돌아간다.
          if (context.mounted) {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
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

/// 집회 하나를 열어 탭 화면(Shell)으로 들어간다. 방배정은 서버에서 읽고, 없으면 빈 채로 시작한다.
Future<void> openGathering(BuildContext context, Gathering g) async {
  await store.open(
    g.id,
    Event(
      name: g.name,
      startDate: dateOnly(g.start),
      endDate: dateOnly(g.end),
      customFields: [...g.formFields],
    ),
  );
  current.value = g;
  store.applyGathering(g);
  tabIndex.value = settingsTab;
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

  /// 서버를 못 읽은 이유.
  String? error;
  List<Gathering> list = [];
  Map<String, ({int total, int confirmed})> counts = {};

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
    try {
      list = await remote.gatherings();
      counts = remote.signedIn ? await remote.registrationCounts() : {};
    } catch (e) {
      error = errorText(e);
      list = [];
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(Gathering g) async {
    await openGathering(context, g);
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
      if (mounted) await _open(g);
    } catch (e) {
      _snack(errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = error != null;
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
                    text: '$error\n연결되면 [새로고침]을 누르세요.',
                    action: OutlinedButton(
                      onPressed: _load,
                      child: const Text('새로고침'),
                    ),
                  ),
                if (list.isEmpty && !offline)
                  const EmptyNotice(
                    icon: Icons.event_note_outlined,
                    text: '아직 집회가 없습니다. [새 집회]로 시작하세요.',
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
                        onTap: () => _open(g),
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
