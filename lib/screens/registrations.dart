import 'package:flutter/material.dart';

import '../gathering.dart';
import '../main.dart';
import '../main_public.dart' show ApplyPage;
import '../models.dart';
import '../remote.dart';
import '../theme.dart';
import '../widgets/quote_table.dart';
import 'gatherings.dart';

const _tabular = [FontFeature.tabularFigures()];

/// 신청·입금 관리. 입금 내역을 확인하고 확정한다.
class RegistrationsScreen extends StatefulWidget {
  const RegistrationsScreen({super.key});

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  List<Registration>? regs;
  String? error;
  bool loading = false;
  bool busy = false;

  /// null = 전체.
  RegStatus? filter;

  /// 사역자가 한 명이라도 있는 신청만.
  bool ministerOnly = false;
  String query = '';
  String? selectedId;

  /// 일괄 확정할 신청 (입금대기만).
  final checked = <String>{};

  @override
  void initState() {
    super.initState();
    signInCount.addListener(_onSignIn);
    if (current.value != null && remote.signedIn) _load();
  }

  @override
  void dispose() {
    signInCount.removeListener(_onSignIn);
    super.dispose();
  }

  void _onSignIn() {
    if (!mounted) return;
    if (remote.signedIn) {
      _load();
    } else {
      setState(() => regs = null);
    }
  }

  Future<void> _load() async {
    final g = current.value;
    if (g == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      regs = await remote.registrations(g.id);
      checked.removeWhere(
        (id) => !regs!.any((r) => r.id == id && r.status == RegStatus.pending),
      );
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _replace(Registration r) => setState(() {
    final i = regs!.indexWhere((x) => x.id == r.id);
    if (i >= 0) regs![i] = r;
    if (r.status != RegStatus.pending) checked.remove(r.id);
  });

  /// 서버에 저장이 되면 [then] 을 부르고(참석자 반영 등), 그 결과 문장을 [done] 뒤에 붙여 알린다.
  Future<void> _patch(
    Registration r,
    Map<String, dynamic> fields,
    String done, {
    String Function()? then,
  }) async {
    setState(() => busy = true);
    try {
      _replace(await remote.patchRegistration(r.id, fields));
      _snack('$done${then?.call() ?? ''}');
    } catch (e) {
      _snack(errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 입금 확인된 신청의 사람을 참석자로 올린다 (추가·수정만, 빼지는 않는다). 새로 올린 사람 수.
  /// 당일 참석자는 방이 필요 없어 올리지 않는다.
  int _syncConfirmed() {
    final g = current.value;
    if (g == null || regs == null) return 0;
    return store.syncRegistrations(g, regs!, remove: false).added;
  }

  bool _matches(Registration r) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final d = digitsOnly(q);
    return r.people.any((p) => p.name.toLowerCase().contains(q)) ||
        r.depositorName.toLowerCase().contains(q) ||
        (d.length >= 3 && r.phone.contains(d));
  }

  @override
  Widget build(BuildContext context) {
    final g = current.value;
    if (g == null) {
      return const EmptyNotice(
        icon: Icons.cloud_off_outlined,
        text: '서버에 연결된 집회에서만 신청을 볼 수 있습니다.',
      );
    }
    if (!remote.signedIn) {
      return EmptyNotice(
        icon: Icons.lock_outline,
        text: '신청·입금 관리는 운영자 로그인이 필요합니다.',
        action: FilledButton(
          onPressed: () async {
            if (await ensureAdmin(context)) _load();
          },
          child: const Text('운영자 로그인'),
        ),
      );
    }
    if (regs == null) {
      return loading
          ? const Center(child: CircularProgressIndicator())
          : EmptyNotice(
              icon: Icons.cloud_off_outlined,
              text: error ?? '신청을 불러오지 못했습니다.',
              action: OutlinedButton(
                onPressed: _load,
                child: const Text('다시 시도'),
              ),
            );
    }

    final all = regs!;
    final quotes = {
      for (final r in all)
        r.id: g.quoteFor(r.people, r.createdAt, discount: r.discount),
    };
    final shown = [
      for (final r in all)
        if ((filter == null || r.status == filter) &&
            (!ministerOnly || _hasMinister(r)) &&
            _matches(r))
          r,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final active = all.where((r) => r.status != RegStatus.cancelled);
    final pendingSum = active
        .where((r) => r.status == RegStatus.pending)
        .fold(0, (s, r) => s + quotes[r.id]!.total);
    final paidSum = active
        .where((r) => r.status == RegStatus.confirmed)
        .fold(0, (s, r) => s + r.paid);
    final selected = all.where((r) => r.id == selectedId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatCard('신청', '${active.length}', unit: '건'),
              StatCard(
                '인원',
                '${active.fold(0, (s, r) => s + r.people.length)}',
                unit: '명',
              ),
              StatCard(
                '입금대기 금액',
                _n(pendingSum),
                unit: '원',
                color: AppColors.warn,
              ),
              StatCard('입금 확인', _n(paidSum), unit: '원', color: AppColors.ok),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in [null, ...RegStatus.values])
                ChoiceChip(
                  label: Text(
                    '${f?.labelFor(free: g.fee.isFree) ?? '전체'} ${all.where((r) => f == null || r.status == f).length}',
                  ),
                  selected: filter == f,
                  onSelected: (_) => setState(() => filter = f),
                ),
              if (g.asks('minister') || all.any(_hasMinister))
                FilterChip(
                  label: Text('사역자 ${all.where(_hasMinister).length}'),
                  selected: ministerOnly,
                  onSelected: (v) => setState(() => ministerOnly = v),
                ),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: '이름 · 입금자명 · 휴대폰',
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('새로고침'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _add(g),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('신청 추가'),
              ),
              FilledButton.icon(
                onPressed: checked.isEmpty || busy
                    ? null
                    : () => _bulkConfirm(quotes),
                icon: const Icon(Icons.done_all, size: 18),
                label: Text('선택 ${checked.length}건 입금 확인'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: shown.isEmpty
                    ? EmptyNotice(
                        icon: Icons.inbox_outlined,
                        text: all.isEmpty
                            ? '아직 신청이 없습니다.\n[집회 설정]에서 신청 링크를 복사해 공지하세요.'
                            : '조건에 맞는 신청이 없습니다.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Header(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final r = shown[i];
                                return _RegRow(
                                  r: r,
                                  q: quotes[r.id]!,
                                  selected: r.id == selectedId,
                                  checked: checked.contains(r.id),
                                  onTap: () => setState(
                                    () => selectedId = selectedId == r.id
                                        ? null
                                        : r.id,
                                  ),
                                  onCheck: (v) => setState(
                                    () => v
                                        ? checked.add(r.id)
                                        : checked.remove(r.id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              if (selected != null) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 400,
                  child: _Detail(
                    r: selected,
                    q: quotes[selected.id]!,
                    busy: busy,
                    onClose: () => setState(() => selectedId = null),
                    onConfirm: () => _confirm(selected, quotes[selected.id]!),
                    onRevert: () => _patch(selected, {
                      'status': 'pending',
                      'paid': 0,
                      'paid_at': null,
                    }, '입금대기로 되돌렸습니다.'),
                    onCancel: () => _cancel(selected),
                    onResetPin: () => _resetPin(selected),
                    onDelete: () => _delete(selected),
                    onDiscount: (d) => _patch(selected, {
                      'discount_pct': d.pct,
                      'discount_amount': d.amount,
                      'discount_note': d.note,
                    }, d.isEmpty ? '지정 할인을 해제했습니다.' : '지정 할인을 적용했습니다.'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 전화·현장 접수. 신청 웹과 같은 신청서로 받아 입금대기로 넣고, 그 신청을 열어 둔다 —
  /// 입금 확인·지정 할인은 다른 신청과 똑같이 여기서 한다.
  Future<void> _add(Gathering g) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ApplyPage(gathering: g, admin: true)),
    );
    if (id == null) return;
    await _load();
    if (!mounted) return;
    setState(() => selectedId = id);
    _snack('신청을 추가했습니다. 입금이 확인되면 [입금 확인]을 누르세요.');
  }

  Future<void> _confirm(Registration r, Quote q) async {
    final amount = TextEditingController(text: '${q.total}');
    final dep = TextEditingController(text: r.depositorName);
    var date = dateOnly(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final n = int.tryParse(digitsOnly(amount.text));
          final diff = n == null ? 0 : n - q.total;
          return AlertDialog(
            title: Text('${r.applicant} 입금 확인'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '계산 금액 ${won(q.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '입금액',
                      suffixText: '원',
                      errorText: n == null ? '숫자로 입력하세요' : null,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (diff != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '계산 금액보다 ${won(diff.abs())} ${diff > 0 ? '더' : '덜'} 들어왔습니다. 그래도 확정할 수 있습니다.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warnInk,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dep,
                    decoration: const InputDecoration(labelText: '입금자명'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('입금일 ${date.year}-${mdw(date)}'),
                    onPressed: () async {
                      final d = await pickDate(context, date);
                      if (d != null) setLocal(() => date = d);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('닫기'),
              ),
              FilledButton(
                onPressed: n == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('확정'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await _patch(
      r,
      {
        'status': 'confirmed',
        'paid': int.parse(digitsOnly(amount.text)),
        'paid_at': ymd(date),
        'depositor': dep.text.trim().isEmpty ? null : dep.text.trim(),
      },
      '${r.applicant} 입금 확인했습니다.',
      then: () {
        final n = _syncConfirmed();
        return n > 0 ? ' 참석자 $n명을 등록했습니다.' : '';
      },
    );
  }

  Future<void> _bulkConfirm(Map<String, Quote> quotes) async {
    final targets = [
      for (final r in regs!)
        if (checked.contains(r.id) && r.status == RegStatus.pending) r,
    ];
    final sum = targets.fold(0, (s, r) => s + quotes[r.id]!.total);
    final ok = await confirmDialog(
      context,
      title: '${targets.length}건 입금 확인',
      body: '각 신청의 계산 금액 그대로(합계 ${won(sum)}) 오늘 날짜로 입금 확인합니다.',
      action: '확정',
    );
    if (!ok) return;
    setState(() => busy = true);
    var fail = 0;
    for (final r in targets) {
      try {
        _replace(
          await remote.patchRegistration(r.id, {
            'status': 'confirmed',
            'paid': quotes[r.id]!.total,
            'paid_at': ymd(DateTime.now()),
          }),
        );
      } catch (_) {
        fail++;
      }
    }
    final added = _syncConfirmed();
    if (!mounted) return;
    setState(() => busy = false);
    _snack(
      (fail == 0
              ? '${targets.length}건 입금 확인했습니다.'
              : '${targets.length - fail}건 확인, $fail건 실패. 새로고침 후 다시 시도하세요.') +
          (added > 0 ? ' 참석자 $added명을 등록했습니다.' : ''),
    );
  }

  /// 신청을 서버에서 지운다 (입금 내역 포함). 이 신청으로 들어온 참석자도 뺀다.
  Future<void> _delete(Registration r) async {
    final people = store.event.attendees
        .where((a) => a.registrationId == r.id)
        .length;
    final ok = await confirmDialog(
      context,
      title: '${r.applicant} 신청 삭제',
      body:
          '신청과 입금 내역이 서버에서 완전히 지워지고 되돌릴 수 없습니다. '
          '신청자가 조회해도 나오지 않습니다.'
          '${people > 0 ? '\n이 신청으로 들어온 참석자 $people명도 방배정에서 빠집니다.' : ''}',
      action: '삭제',
      danger: true,
    );
    if (!ok) return;
    setState(() => busy = true);
    try {
      await remote.deleteRegistration(r.id);
      store.removeRegistration(r.id);
      setState(() {
        regs!.removeWhere((x) => x.id == r.id);
        checked.remove(r.id);
        selectedId = null;
      });
      _snack('신청을 삭제했습니다.');
    } catch (e) {
      _snack(errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel(Registration r) async {
    final memo = TextEditingController(text: r.adminMemo ?? '');
    // 취소하면 이 신청의 참석자도 빠진다. 방이 배정된 사람이 있으면 미리 알려준다.
    final inRooms = store.event.attendees
        .where((a) => a.registrationId == r.id && a.roomId != null)
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${r.applicant} 신청 취소'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                r.status == RegStatus.confirmed
                    ? '입금이 확인된 신청입니다. 환불 여부를 메모해 두세요.'
                    : '신청을 취소합니다. 신청자가 조회하면 "취소"로 보입니다.',
              ),
              if (inRooms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '방이 배정된 ${inRooms.length}명'
                  '(${inRooms.take(3).map((a) => a.name).join(', ')}'
                  '${inRooms.length > 3 ? ' 외' : ''})도 참석자에서 빠지고 방 배정이 풀립니다.',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: memo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '운영자 메모 (신청자에게 안 보임)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _patch(
      r,
      {
        'status': 'cancelled',
        'admin_memo': memo.text.trim().isEmpty ? null : memo.text.trim(),
      },
      '${r.applicant} 신청을 취소했습니다.',
      then: () {
        final n = store.removeRegistration(r.id);
        return n > 0 ? ' 참석자 $n명을 뺐습니다.' : '';
      },
    );
  }

  Future<void> _resetPin(Registration r) async {
    final pin = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('PIN 재설정'),
          content: SizedBox(
            width: 320,
            child: TextField(
              controller: pin,
              autofocus: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '새 PIN (숫자 4자리)',
                helperText: '신청자에게 알려줄 번호입니다. 조회 잠금도 같이 풀립니다.',
                errorText: err,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () {
                if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) {
                  setLocal(() => err = '숫자 4자리를 입력하세요');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('바꾸기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await remote.resetPin(r.id, pin.text);
      _snack('새 PIN ${pin.text} — ${r.applicant}님께 알려주세요.');
    } catch (e) {
      _snack(errorText(e));
    }
  }
}

/// 지정 할인 입력. 신청 1건(혼자면 그 사람, 가족·그룹이면 전체)에 % 또는 원으로 준다.
class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({
    super.key,
    required this.r,
    required this.busy,
    required this.onSave,
  });
  final Registration r;
  final bool busy;
  final ValueChanged<Discount> onSave;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  late final Discount d = widget.r.discount;
  late bool pct = d.amount <= 0;
  late final value = TextEditingController(
    text: d.isEmpty ? '' : '${pct ? d.pct : d.amount}',
  );
  late final note = TextEditingController(text: d.note ?? '');
  String? err;

  @override
  void dispose() {
    value.dispose();
    note.dispose();
    super.dispose();
  }

  void _apply() {
    final n = int.tryParse(digitsOnly(value.text));
    if (n == null || n <= 0 || (pct && n > 100)) {
      setState(() => err = pct ? '1~100 사이로 입력하세요' : '금액을 숫자로 입력하세요');
      return;
    }
    setState(() => err = null);
    final t = note.text.trim();
    widget.onSave(
      Discount(
        pct: pct ? n : 0,
        amount: pct ? 0 : n,
        note: t.isEmpty ? null : t,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('%')),
              ButtonSegment(value: false, label: Text('원')),
            ],
            selected: {pct},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => pct = s.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: value,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: pct ? '할인율' : '할인 금액',
                suffixText: pct ? '%' : '원',
                errorText: err,
              ),
              onSubmitted: (_) => _apply(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: note,
        decoration: const InputDecoration(
          labelText: '사유 (신청자 조회 화면에 보임)',
          hintText: '예) 봉사자, 셋째 자녀',
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: widget.busy ? null : _apply,
            child: const Text('할인 적용'),
          ),
          TextButton(
            onPressed: widget.busy || widget.r.discount.isEmpty
                ? null
                : () {
                    value.clear();
                    note.clear();
                    widget.onSave(Discount.none);
                  },
            child: const Text('해제'),
          ),
        ],
      ),
    ],
  );
}

bool _hasMinister(Registration r) => r.people.any((p) => p.minister);

String _n(int n) => won(n).replaceAll('원', '');

String _stay(Quote q) {
  final full = q.lines.where((l) => l.full).length;
  final part = q.lines.length - full;
  return [if (full > 0) '전체 $full', if (part > 0) '부분 $part'].join(' · ');
}

/// 목록의 열 폭. 머리글과 행이 같은 값을 쓴다.
const _wCheck = 40.0, _wDate = 84.0, _wStay = 104.0, _wMoney = 100.0;
const _wName = 100.0, _wStatus = 80.0, _wWarn = 48.0;

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    Widget h(String t, double? w, {bool right = false}) {
      final text = Text(
        t,
        textAlign: right ? TextAlign.right : null,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: _wCheck),
          h('신청일', _wDate),
          h('신청자', null),
          h('일정', _wStay),
          h('금액', _wMoney, right: true),
          const SizedBox(width: 12),
          h('입금자명', _wName),
          h('입금액', _wMoney, right: true),
          const SizedBox(width: 12),
          h('상태', _wStatus),
          const SizedBox(width: _wWarn),
        ],
      ),
    );
  }
}

class _RegRow extends StatelessWidget {
  const _RegRow({
    required this.r,
    required this.q,
    required this.selected,
    required this.checked,
    required this.onTap,
    required this.onCheck,
  });
  final Registration r;
  final Quote q;
  final bool selected, checked;
  final VoidCallback onTap;
  final ValueChanged<bool> onCheck;

  @override
  Widget build(BuildContext context) {
    final mismatch = r.quoted != q.beforeDiscount;
    final diff = r.status == RegStatus.confirmed ? r.paid - q.total : 0;
    return Material(
      color: selected ? AppColors.brandSoft : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: _wCheck,
                child: r.status == RegStatus.pending
                    ? Checkbox(
                        value: checked,
                        onChanged: (v) => onCheck(v == true),
                      )
                    : null,
              ),
              SizedBox(
                width: _wDate,
                child: Text(
                  mdw(r.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.applicant,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_hasMinister(r)) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '사역자',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      q.specialDiscount > 0
                          ? '${q.summary} · 지정 할인'
                          : q.summary,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _wStay,
                child: Text(_stay(q), style: const TextStyle(fontSize: 12)),
              ),
              SizedBox(
                width: _wMoney,
                child: Text(
                  won(q.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _wName,
                child: Text(
                  r.depositorName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(
                width: _wMoney,
                child: Text(
                  r.status == RegStatus.confirmed ? won(r.paid) : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFeatures: _tabular),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _wStatus,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RegStatusBadge(
                    r.status,
                    free: current.value?.fee.isFree ?? false,
                  ),
                ),
              ),
              SizedBox(
                width: _wWarn,
                child: Row(
                  children: [
                    if (mismatch)
                      Tooltip(
                        message:
                            '신청 때 보여준 금액(${won(r.quoted)})과 지금 계산 금액이 다릅니다.\n'
                            '신청 뒤 회비 설정이 바뀌었거나 값이 조작된 경우입니다.',
                        child: const Icon(
                          Icons.warning_amber,
                          size: 18,
                          color: AppColors.warn,
                        ),
                      ),
                    if (diff != 0)
                      Tooltip(
                        message:
                            '입금액이 계산 금액보다 ${won(diff.abs())} ${diff > 0 ? '많습니다' : '적습니다'}.',
                        child: const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: AppColors.danger,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.r,
    required this.q,
    required this.busy,
    required this.onClose,
    required this.onConfirm,
    required this.onRevert,
    required this.onCancel,
    required this.onResetPin,
    required this.onDelete,
    required this.onDiscount,
  });
  final Registration r;
  final Quote q;
  final bool busy;
  final VoidCallback onClose, onConfirm, onRevert, onCancel, onResetPin;
  final VoidCallback onDelete;
  final ValueChanged<Discount> onDiscount;

  @override
  Widget build(BuildContext context) {
    final t = r.createdAt;
    // 부분 참석자의 고른 날짜 (사람 id → "10-09(금) 10-10(토)").
    final days = {
      for (final l in q.lines)
        if (!l.full) l.person.id: l.days.map(mdw).join(' '),
    };
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                r.applicant,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            RegStatusBadge(r.status, free: current.value?.fee.isFree ?? false),
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
        Text(
          '${fmtPhone(r.phone)} · 신청 ${ymd(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        const SectionTitle('금액'),
        const SizedBox(height: 8),
        QuoteTable(q),
        if (r.quoted != q.beforeDiscount)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '신청 때 보여준 금액: ${won(r.quoted)}',
              style: const TextStyle(fontSize: 12, color: AppColors.warnInk),
            ),
          ),
        if (r.status != RegStatus.cancelled) ...[
          const SizedBox(height: 16),
          const SectionTitle('지정 할인'),
          const SizedBox(height: 8),
          _DiscountEditor(
            key: ValueKey(r.id),
            r: r,
            busy: busy,
            onSave: onDiscount,
          ),
        ],
        const SizedBox(height: 16),
        const SectionTitle('참석자'),
        const SizedBox(height: 6),
        for (final p in r.people)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(
              TextSpan(
                text: p.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text:
                        '  ${p.relation}'
                        '${p.gender.isEmpty ? '' : ' · ${genderLabel(p.gender)}'}'
                        '${p.birthYear == 0 ? '' : ' · ${p.birthYear}년생'}'
                        '${p.minister ? ' · 사역자${p.church == null ? '' : '(${p.church})'}' : ''}'
                        '${(p.cell ?? '').isNotEmpty ? ' · 셀 ${p.cell}' : ''}'
                        '${(p.zone ?? '').isNotEmpty ? ' · 존 ${p.zone}' : ''}'
                        '${p.extra.entries.map((e) => ' · ${e.key} ${e.value}').join()}'
                        '${days.containsKey(p.id) ? ' · ${days[p.id]}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const SectionTitle('입금'),
        const SizedBox(height: 6),
        kv('입금자명', r.depositorName),
        if (r.status == RegStatus.confirmed) ...[
          kv('입금액', won(r.paid)),
          if (r.paidAt != null) kv('입금일', ymd(r.paidAt!)),
        ],
        if ((r.memo ?? '').isNotEmpty) kv('신청 메모', r.memo!),
        if ((r.adminMemo ?? '').isNotEmpty) kv('운영자 메모', r.adminMemo!),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (r.status == RegStatus.pending)
              FilledButton.icon(
                onPressed: busy ? null : onConfirm,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('입금 확인'),
              )
            else
              OutlinedButton(
                onPressed: busy ? null : onRevert,
                child: const Text('입금대기로 되돌리기'),
              ),
            if (r.status != RegStatus.cancelled)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: busy ? null : onCancel,
                child: const Text('신청 취소'),
              ),
            TextButton(
              onPressed: busy ? null : onResetPin,
              child: const Text('PIN 재설정'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: busy ? null : onDelete,
              child: const Text('신청 삭제'),
            ),
          ],
        ),
      ],
    );
  }
}
