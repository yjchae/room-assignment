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
  String? err, info;
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    pw.dispose();
    super.dispose();
  }

  /// [f] 를 돌리는 동안 버튼을 막고, 실패하면 에러 문구를 띄운다.
  Future<void> _run(Future<void> Function() f) async {
    if (busy) return;
    setState(() {
      busy = true;
      err = info = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _go() => _run(() async {
    await remote.signIn(email.text, pw.text);
    widget.onDone();
  });

  Future<void> _forgot() => _run(() async {
    if (!email.text.contains('@')) throw const RemoteError('이메일을 먼저 입력하세요.');
    await remote.sendPasswordReset(email.text);
    info =
        '비밀번호 재설정 메일을 보냈습니다. 메일의 링크를 이 브라우저에서 열어 새 비밀번호를 정하세요. '
        '메일이 안 오면 스팸함을 확인하세요.';
  });

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
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: busy ? null : _forgot,
              child: const Text('비밀번호를 잊었어요', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => const _SignUpDialog(),
                    ),
              child: const Text('운영자 가입 신청', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (info != null)
          Text(
            info!,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
      ],
    ),
  );
}

/// 새 비밀번호 입력. [askCurrent] 면 지금 비밀번호부터 확인한다.
/// 재설정 메일 링크로 들어왔을 땐(첫 화면) 안 묻는다.
class PasswordForm extends StatefulWidget {
  const PasswordForm({
    super.key,
    required this.askCurrent,
    required this.onDone,
  });
  final bool askCurrent;
  final VoidCallback onDone;

  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<PasswordForm> {
  final cur = TextEditingController();
  final next = TextEditingController();
  final again = TextEditingController();
  String? err;
  bool busy = false;

  @override
  void dispose() {
    cur.dispose();
    next.dispose();
    again.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (busy) return;
    if (next.text.isEmpty || next.text != again.text) {
      setState(() => err = '새 비밀번호를 똑같이 두 번 입력하세요.');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await remote.changePassword(
        widget.askCurrent ? cur.text : null,
        next.text,
      );
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
        if (widget.askCurrent) ...[
          TextField(
            controller: cur,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: '지금 비밀번호'),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: next,
          autofocus: !widget.askCurrent,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: '새 비밀번호'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: again,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: '새 비밀번호 확인',
            errorText: err,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : _go,
          child: Text(busy ? '바꾸는 중…' : '비밀번호 바꾸기'),
        ),
      ],
    ),
  );
}

Future<void> _changePasswordDialog(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('비밀번호 변경'),
      content: SizedBox(
        width: 340,
        child: PasswordForm(
          askCurrent: true,
          onDone: () {
            Navigator.pop(context);
            messenger.showSnackBar(
              const SnackBar(content: Text('비밀번호를 바꿨습니다.')),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
      ],
    ),
  );
}

/// 운영자 가입 신청. 기존 운영자가 [운영자 승인]에서 승인해야 로그인할 수 있다.
class _SignUpDialog extends StatefulWidget {
  const _SignUpDialog();

  @override
  State<_SignUpDialog> createState() => _SignUpDialogState();
}

class _SignUpDialogState extends State<_SignUpDialog> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pw = TextEditingController();
  final again = TextEditingController();
  String? err;
  bool busy = false, done = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    pw.dispose();
    again.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (busy) return;
    final bad = name.text.trim().isEmpty
        ? '이름을 입력하세요.'
        : !email.text.contains('@')
        ? '이메일을 확인하세요.'
        : pw.text.isEmpty || pw.text != again.text
        ? '비밀번호를 똑같이 두 번 입력하세요.'
        : null;
    setState(() {
      err = bad;
      busy = bad == null;
    });
    if (bad != null) return;
    try {
      await remote.signUp(name.text, email.text, pw.text);
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('운영자 가입 신청'),
    content: SizedBox(
      width: 340,
      child: done
          ? const Text(
              '가입 신청을 보냈습니다.\n'
              '기존 운영자가 승인하면 로그인할 수 있습니다. '
              '확인 메일이 오면 메일의 링크도 눌러 주세요.',
            )
          : AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: '이름'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pw,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: '비밀번호'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: again,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: '비밀번호 확인',
                      errorText: err,
                      errorMaxLines: 3,
                    ),
                    onSubmitted: (_) => _go(),
                  ),
                ],
              ),
            ),
    ),
    actions: done
        ? [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ]
        : [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy ? null : _go,
              child: Text(busy ? '보내는 중…' : '가입 신청'),
            ),
          ],
  );
}

/// 가입 신청 목록. 승인하면 운영자가 되고, 거절하면 그 계정이 지워진다.
class _AdminRequestsDialog extends StatefulWidget {
  const _AdminRequestsDialog();

  @override
  State<_AdminRequestsDialog> createState() => _AdminRequestsDialogState();
}

class _AdminRequestsDialogState extends State<_AdminRequestsDialog> {
  late Future<List<AdminRequest>> list = remote.adminRequests();
  String? err;

  Future<void> _act(Future<void> Function() f) async {
    setState(() => err = null);
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
    }
    if (mounted) {
      setState(() {
        list = remote.adminRequests();
      });
    }
  }

  Future<void> _reject(AdminRequest r) async {
    final ok = await confirmDialog(
      context,
      title: '가입 거절',
      body: '${r.email} 계정을 지웁니다. 다시 쓰려면 가입 신청부터 다시 해야 합니다.',
      action: '거절',
      danger: true,
    );
    if (ok) await _act(() => remote.rejectAdmin(r.id));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('운영자 승인'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: FutureBuilder(
        future: list,
        builder: (context, s) {
          if (s.hasError) return Text(errorText(s.error!));
          final rs = s.data;
          if (rs == null) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (err != null)
                Text(err!, style: const TextStyle(color: AppColors.danger)),
              if (rs.isEmpty) const Text('승인을 기다리는 가입 신청이 없습니다.'),
              for (final r in rs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name.isEmpty ? r.email : r.name),
                  subtitle: Text('${r.email} · ${ymd(r.at)} 신청'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _reject(r),
                        child: const Text('거절'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => _act(() => remote.approveAdmin(r.id)),
                        child: const Text('승인'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
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
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          icon: const Icon(Icons.login, size: 16),
          label: const Text('운영자 로그인', style: TextStyle(fontSize: 13)),
          onPressed: () => ensureAdmin(context),
        );
      }
      return PopupMenuButton<String>(
        tooltip: '운영자 계정',
        onSelected: (v) async {
          if (v == 'pw') return _changePasswordDialog(context);
          if (v == 'approve') {
            return showDialog<void>(
              context: context,
              builder: (_) => const _AdminRequestsDialog(),
            );
          }
          await remote.signOut();
          signInCount.value++;
          // 집회 탭 화면에서 로그아웃해도 첫 화면(로그인)으로 돌아간다.
          if (context.mounted) {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'approve', child: Text('운영자 승인')),
          PopupMenuItem(value: 'pw', child: Text('비밀번호 변경')),
          PopupMenuItem(value: 'out', child: Text('로그아웃')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_circle_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
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
