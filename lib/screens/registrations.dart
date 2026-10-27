import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../bank_import.dart';
import '../gathering.dart';
import '../main.dart';
import '../main_public.dart' show ApplyPage;
import '../models.dart';
import '../remote.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets/quote_table.dart';
import 'attendees.dart' show pasteDialog;
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

  /// 무료 날만 당일로 오는 사람(`QuoteLine.freeDay`)이 있는 신청만. 할인으로 0원이 된 사람은 아니다.
  bool freeDayOnly = false;
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
      _syncPlan(); // 새로 들어온 신청도 바로 참석자(홈스테이는 가정)에 보이게
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

  /// 서버에 저장이 되면 [then] 을 부르고 방배정에 반영한 뒤([_syncPlan]), 그 결과 문장을 [done] 뒤에 붙여 알린다.
  Future<void> _patch(
    Registration r,
    Map<String, dynamic> fields,
    String done, {
    String Function()? then,
  }) async {
    setState(() => busy = true);
    try {
      _replace(await remote.patchRegistration(r.id, fields));
      _snack('$done${then?.call() ?? ''}${_syncPlan()}');
    } catch (e) {
      _snack(errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 신청 목록을 방배정에 반영한다 — 입금대기도 올리고 입금 상태를 맞추고, 취소된 신청은
  /// 방이 있어도 뺀다 ([Store.syncFromRegistrations]). 알림에 덧붙일 문장.
  ///
  /// - 집회: 신청의 사람을 참석자로 올린다. 당일 참석자는 방이 필요 없어 올리지 않는다.
  /// - 홈스테이: 신청자 이름으로 방(가정)을 만든다.
  String _syncPlan() {
    final g = current.value;
    if (g == null || regs == null) return '';
    final n = store.syncFromRegistrations(g, regs!);
    final unit = g.isHomestay ? '곳' : '명';
    return [
      if (n.added > 0)
        g.isHomestay ? ' 가정 ${n.added}곳을 방으로 만들었습니다.' : ' 참석자 ${n.added}명을 등록했습니다.',
      if (n.removed > 0) ' 취소된 신청의 ${g.isHomestay ? '가정' : '참석자'} ${n.removed}$unit을 뺐습니다.',
    ].join();
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
            (!freeDayOnly || quotes[r.id]!.lines.any((l) => l.freeDay)) &&
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
    final size = windowSizeOf(context);
    Widget detailOf(Registration selected) => _Detail(
      r: selected,
      q: quotes[selected.id]!,
      busy: busy,
      onClose: () => setState(() => selectedId = null),
      onConfirm: () => _confirm(selected, quotes[selected.id]!),
      onRevert: () => _patch(selected, {
        'status': 'pending',
        'paid': 0,
        'paid_at': null,
        'paid_ref': null,
      }, '입금대기로 되돌렸습니다.'),
      onCancel: () => _cancel(selected),
      onResetPin: () => _resetPin(selected),
      onDelete: () => _delete(selected),
      onDiscount: (d) => _patch(selected, {
        'discount_pct': d.pct,
        'discount_amount': d.amount,
        'discount_note': d.note,
      }, d.isEmpty ? '지정 할인을 해제했습니다.' : '지정 할인을 적용했습니다.'),
    );
    // 휴대폰: 상세가 목록 자리를 통째로 쓴다. 뒤로 가기(제스처·버튼)는 상세만 닫는다.
    if (size.isCompact && selected != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => selectedId = null);
        },
        child: detailOf(selected),
      );
    }

    // 신청이 아니라 사람 수로 센다 — 가족 중 한 명만 무료 날 당일로 올 수 있다.
    final freeDayPeople = all.fold(
      0,
      (n, r) => n + quotes[r.id]!.lines.where((l) => l.freeDay).length,
    );
    final chips = <Widget>[
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
      // 집회 설정에 무료 날이 있을 때만.
      if (g.fee.freeDays.isNotEmpty)
        FilterChip(
          label: Text('무료 날 당일 $freeDayPeople명'),
          tooltip: '무료 날 하루만 당일로 오는 사람이 있는 신청 (할인으로 0원인 신청은 빠집니다)',
          selected: freeDayOnly,
          onSelected: (v) => setState(() => freeDayOnly = v),
        ),
    ];
    final Widget table = shown.isEmpty
        ? EmptyNotice(
            icon: Icons.inbox_outlined,
            text: all.isEmpty
                ? '아직 신청이 없습니다.\n[집회 설정]에서 신청 링크를 복사해 공지하세요.'
                : '조건에 맞는 신청이 없습니다.',
          )
        // 창이 좁거나 오른쪽 상세가 열려 폭이 모자라면 열을 찌그러뜨리지 않고 가로로 굴린다.
        : LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: box.maxWidth < _minTableWidth
                    ? _minTableWidth
                    : box.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = shown[i];
                          return _RegRow(
                            r: r,
                            q: quotes[r.id]!,
                            selected: r.id == selectedId,
                            checked: checked.contains(r.id),
                            onTap: () => setState(
                              () =>
                                  selectedId = selectedId == r.id ? null : r.id,
                            ),
                            onCheck: (v) => setState(
                              () =>
                                  v ? checked.add(r.id) : checked.remove(r.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            size.isCompact ? 12 : 16,
            size.isCompact ? 12 : 16,
            size.isCompact ? 12 : 16,
            8,
          ),
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
              StatCard(
                '입금 확인 (자동 ${active.where((r) => r.status == RegStatus.confirmed && r.autoPaid).length}'
                ' · 수동 ${active.where((r) => r.status == RegStatus.confirmed && !r.autoPaid).length})',
                _n(paidSum),
                unit: '원',
                color: AppColors.ok,
              ),
            ],
          ),
        ),
        if (size.isCompact)
          _compactTools(g, quotes, chips)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...chips,
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
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _paste(g),
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('붙여넣기 추가'),
                ),
                FilledButton.icon(
                  onPressed: checked.isEmpty || busy
                      ? null
                      : () => _bulkConfirm(quotes),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text('선택 ${checked.length}건 입금 확인'),
                ),
                if (!g.fee.isFree)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _importBank(quotes),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('은행 내역 올리기'),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: switch (size) {
            // 데스크톱: [표 | 상세 400] 나란히.
            WindowSize.expanded => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: table),
                if (selected != null) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 400, child: detailOf(selected)),
                ],
              ],
            ),
            // 태블릿: 상세가 표 폭을 뺏지 않게 오른쪽에 겹쳐 띄운다.
            WindowSize.medium => Stack(
              children: [
                Positioned.fill(child: table),
                if (selected != null)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 400,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(
                          left: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: detailOf(selected),
                    ),
                  ),
              ],
            ),
            // 휴대폰: 표 대신 두 줄짜리 카드. 누르면 상세가 화면을 채운다(위 PopScope).
            WindowSize.compact =>
              shown.isEmpty
                  ? table
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = shown[i];
                        return _RegCard(
                          r: r,
                          q: quotes[r.id]!,
                          checked: checked.contains(r.id),
                          onTap: () => setState(() => selectedId = r.id),
                          onCheck: (v) => setState(
                            () => v ? checked.add(r.id) : checked.remove(r.id),
                          ),
                        );
                      },
                    ),
          },
        ),
      ],
    );
  }

  /// 휴대폰 도구 줄: [검색] / [상태 칩 가로 스크롤] / [선택 입금 확인 | ⋮].
  /// 버튼 여섯 개를 늘어놓으면 화면 절반이 버튼이라, 자주 쓰는 하나만 꺼내고 나머지는 메뉴로.
  Widget _compactTools(
    Gathering g,
    Map<String, Quote> quotes,
    List<Widget> chips,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: '이름 · 입금자명 · 휴대폰',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, c) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                c,
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: checked.isEmpty || busy
                    ? null
                    : () => _bulkConfirm(quotes),
                icon: const Icon(Icons.done_all, size: 18),
                label: Text('선택 ${checked.length}건 입금 확인'),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: '더보기',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => switch (v) {
                'refresh' => _load(),
                'add' => _add(g),
                'paste' => _paste(g),
                _ => _importBank(quotes),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'refresh',
                  enabled: !loading,
                  child: const Text('새로고침'),
                ),
                PopupMenuItem(
                  value: 'add',
                  enabled: !busy,
                  child: const Text('신청 추가'),
                ),
                PopupMenuItem(
                  value: 'paste',
                  enabled: !busy,
                  child: const Text('붙여넣기 추가'),
                ),
                if (!g.fee.isFree)
                  PopupMenuItem(
                    value: 'bank',
                    enabled: !busy,
                    child: const Text('은행 내역 올리기'),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

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

  /// 엑셀 명단을 붙여넣어 신청 여러 건을 한 번에 넣는다. 전화번호가 같은 사람은 한 신청(가족)으로
  /// 묶는다 — 서버가 집회당 전화번호 하나에 신청 하나만 받아서. 모두 전체 참석·입금대기로 들어가고,
  /// PIN 은 무작위라 신청자가 조회하려면 [PIN 재설정]으로 알려 준다.
  Future<void> _paste(Gathering g) async {
    final rows = await pasteDialog(
      context,
      title: '붙여넣기로 신청 추가',
      help: '전화번호가 같은 사람은 한 신청(가족)으로 묶습니다. 모두 입금대기로 들어갑니다.',
      requirePhone: true,
    );
    if (rows == null || !mounted) return;
    final byPhone = <String, List<Attendee>>{};
    for (final a in rows) {
      byPhone.putIfAbsent(digitsOnly(a.phone!), () => []).add(a);
    }
    setState(() => busy = true);
    var added = 0;
    final failed = <String>[];
    for (final MapEntry(key: phone, value: list) in byPhone.entries) {
      final people = [
        for (final a in list)
          Person(
            name: a.name,
            gender: a.gender,
            birthYear: g.start.year - a.age,
            phone: phone,
            cell: a.cell,
            zone: a.zone,
            extra: a.extra,
          ),
      ];
      final notes = [for (final a in list) ?a.note].join(', ');
      try {
        await remote.adminSubmit(
          g.id,
          phone: phone,
          pin: '${math.Random.secure().nextInt(10000)}'.padLeft(4, '0'),
          people: people,
          memo: notes.isEmpty ? null : notes,
          quoted: g.quoteFor(people, DateTime.now()).beforeDiscount,
        );
        added++;
      } catch (e) {
        failed.add('${people.first.name}(${fmtPhone(phone)}): ${errorText(e)}');
      }
    }
    if (!mounted) return;
    setState(() => busy = false);
    await _load();
    if (!mounted) return;
    _snack(
      [
        '신청 $added건을 입금대기로 추가했습니다.',
        if (failed.isNotEmpty) '못 넣은 신청 ${failed.length}건:',
        ...failed,
      ].join('\n'),
    );
  }

  Future<void> _confirm(Registration r, Quote q) async {
    // 무료 날 당일만인 신청(날짜 없는 집회는 전원 미참가)은 금액·입금자 없이 바로 확정.
    // ponytail: 무료 집회는 예전처럼 입금 확인 창을 거친다 — 같이 바꾸려면 freeFor(q) 로.
    if (q.noPayment) {
      return _patch(
        r,
        {
          'status': 'confirmed',
          'paid': 0,
          'paid_at': ymd(DateTime.now()),
          'paid_ref': null,
        },
        '${r.applicant} 신청을 확정했습니다.',
      );
    }
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
        'paid_ref': null,
        'depositor': dep.text.trim().isEmpty ? null : dep.text.trim(),
      },
      '${r.applicant} 입금 확인했습니다.',
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
            'paid_ref': null,
          }),
        );
      } catch (_) {
        fail++;
      }
    }
    final added = _syncPlan();
    if (!mounted) return;
    setState(() => busy = false);
    _snack(
      (fail == 0
              ? '${targets.length}건 입금 확인했습니다.'
              : '${targets.length - fail}건 확인, $fail건 실패. 새로고침 후 다시 시도하세요.') +
          added,
    );
  }

  /// 은행에서 받은 입출금 내역으로 입금을 확인한다. 파일은 이 기기에서만 읽고 어디에도 올리지 않는다
  /// (남의 거래·실명이 들어 있다). 남는 건 맞춘 거래 한 줄(`paid_ref`)뿐이고, 그게 있으면 '자동'으로 보인다.
  Future<void> _importBank(Map<String, Quote> quotes) async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx', 'csv'],
      );
    } catch (e) {
      _snack('파일 선택 창을 열지 못했습니다. ($e)');
      return;
    }
    if (file == null || !mounted) return;
    final List<BankTx> txs;
    try {
      txs = parseBankFile(await file.readAsBytes(), file.name);
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    } catch (_) {
      _snack('파일을 읽지 못했습니다. 은행에서 받은 입출금 내역 파일인지 확인하세요.');
      return;
    }
    if (txs.isEmpty) {
      _snack('${file.name} 에서 입금 거래를 찾지 못했습니다. 입금액이 있는 행이 있는지 확인하세요.');
      return;
    }
    // 무료 날 당일만인 신청은 받을 돈이 없어 대조하지 않는다.
    final g = current.value!;
    final ({List<BankMatch> matches, List<BankTx> unmatched}) result;
    try {
      result = matchDeposits(txs, regs!, {
        for (final r in regs!)
          if (!g.freeFor(quotes[r.id]!)) r.id: quotes[r.id]!.total,
      });
    } catch (e) {
      _snack('입금 대조 중 오류가 났습니다. ($e)');
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<List<BankMatch>>(
      context: context,
      builder: (_) => BankPreview(
        matches: result.matches,
        unmatched: result.unmatched,
        txCount: txs.length,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() => busy = true);
    var fail = 0;
    for (final m in picked) {
      final r = m.reg;
      try {
        _replace(
          await remote.patchRegistration(
            r.id,
            r.status == RegStatus.confirmed
                // 추가 입금: 먼저 받은 금액에 더하고 근거 거래를 덧붙인다.
                ? {
                    'paid': r.paid + m.tx.amount,
                    'paid_ref': [...paidRefs(r), m.tx.ref].join('\n'),
                  }
                : {
                    'status': 'confirmed',
                    'paid': m.tx.amount,
                    'paid_at': ymd(m.tx.at),
                    'paid_ref': m.tx.ref,
                  },
          ),
        );
      } catch (_) {
        fail++;
      }
    }
    final added = _syncPlan();
    if (!mounted) return;
    setState(() => busy = false);
    final off = picked.where((m) {
      final r = regs!.firstWhere((x) => x.id == m.reg.id);
      return r.paid != quotes[r.id]!.total;
    }).length;
    _snack(
      (fail == 0
              ? '은행 내역으로 ${picked.length}건 입금 확인했습니다.'
              : '${picked.length - fail}건 확인, $fail건 실패. 새로고침 후 다시 시도하세요.') +
          (off > 0 ? ' 금액이 다른 $off건은 목록에 차액이 표시됩니다.' : '') +
          added,
    );
  }

  /// 신청을 서버에서 지운다 (입금 내역 포함). 이 신청으로 들어온 참석자도 뺀다.
  Future<void> _delete(Registration r) async {
    final people = store.event.attendees
        .where((a) => a.registrationId == r.id)
        .length;
    final home = store.event.rooms.any((x) => x.registrationId == r.id);
    final losing = store.wouldLoseRoom(r.id).length;
    final ok = await confirmDialog(
      context,
      title: '${r.applicant} 신청 삭제',
      body:
          '신청과 입금 내역이 서버에서 완전히 지워지고 되돌릴 수 없습니다. '
          '신청자가 조회해도 나오지 않습니다.'
          '${home ? '\n이 신청으로 만든 방(가정)도 지워집니다.'
                    '${losing > 0 ? ' 배정돼 있던 $losing명은 미배정으로 돌아갑니다.' : ''}' : ''}'
          '${!home && people > 0 ? '\n이 신청으로 들어온 참석자 $people명도 방배정에서 빠집니다.' : ''}',
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
    // 취소하면 이 신청의 참석자(홈스테이는 그 가정)가 빠진다. 방 배정이 풀리는 사람은 미리 알려준다.
    final home = store.event.rooms.any((x) => x.registrationId == r.id);
    final inRooms = store.wouldLoseRoom(r.id);
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
                  home
                      ? '이 가정에 배정된 ${inRooms.length}명'
                            '(${inRooms.take(3).map((a) => a.name).join(', ')}'
                            '${inRooms.length > 3 ? ' 외' : ''})의 배정이 풀립니다.'
                      : '방이 배정된 ${inRooms.length}명'
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
        if (n.rooms > 0) return ' 가정 ${n.rooms}곳을 방배정에서 뺐습니다.';
        return n.people > 0 ? ' 참석자 ${n.people}명을 뺐습니다.' : '';
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
  // 날짜 없는 집회: 참가 = 전체 참석, 미참가 = 고른 날 없음.
  if (q.lines.any((l) => l.dateless)) {
    return [if (full > 0) '참가 $full', if (part > 0) '미참가 $part'].join(' · ');
  }
  return [if (full > 0) '전체 $full', if (part > 0) '부분 $part'].join(' · ');
}

/// 목록의 열 폭. 머리글과 행이 같은 값을 쓴다.
const _wCheck = 40.0, _wDate = 84.0, _wStay = 104.0, _wMoney = 100.0;
const _wName = 100.0, _wStatus = 80.0, _wWarn = 48.0;

/// 표가 찌그러지지 않는 최소 폭 = 고정 열 + 신청자 칸 160 + 사이 여백·안쪽 여백.
const _minTableWidth =
    _wCheck +
    _wDate +
    160 +
    _wStay +
    _wMoney * 2 +
    _wName +
    _wStatus +
    _wWarn +
    24 +
    16;

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
                  q.noPayment ? '무료' : won(q.total),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r.status == RegStatus.confirmed ? won(r.paid) : '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFeatures: _tabular),
                    ),
                    if (diff != 0) _DiffText(r.paid, q.total),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _wStatus,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 무료 날 당일만이라 0원인 신청도 무료 집회처럼 '대기/확정'.
                    RegStatusBadge(
                      r.status,
                      free: current.value?.freeFor(q) ?? false,
                    ),
                    if (r.status == RegStatus.confirmed &&
                        !(current.value?.freeFor(q) ?? false))
                      _PaidHow(r),
                  ],
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

/// 휴대폰용 신청 한 줄. 표의 열 9개를 두 줄로 접는다.
/// 1줄: [체크] 신청자 · 사역자 · 상태 / 2줄: 신청일 · 일정 · 금액 · 경고.
class _RegCard extends StatelessWidget {
  const _RegCard({
    required this.r,
    required this.q,
    required this.checked,
    required this.onTap,
    required this.onCheck,
  });
  final Registration r;
  final Quote q;
  final bool checked;
  final VoidCallback onTap;
  final ValueChanged<bool> onCheck;

  @override
  Widget build(BuildContext context) {
    final mismatch = r.quoted != q.beforeDiscount;
    final diff = r.status == RegStatus.confirmed ? r.paid - q.total : 0;
    final free = current.value?.freeFor(q) ?? false;
    const muted = TextStyle(fontSize: 12, color: AppColors.textMuted);
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              // 입금대기만 체크할 수 있다. 자리는 늘 비워 둬서 이름 줄이 흔들리지 않게.
              SizedBox(
                width: 48,
                child: r.status == RegStatus.pending
                    ? Checkbox(
                        value: checked,
                        onChanged: (v) => onCheck(v == true),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 이름이 길면 이름만 줄이고 상태 배지는 늘 오른쪽 끝에.
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  r.applicant,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_hasMinister(r))
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text(
                                    '사역자',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        RegStatusBadge(r.status, free: free),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${mdw(r.createdAt)} 신청 · ${_stay(q)}',
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                        if (mismatch)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.warning_amber,
                              size: 16,
                              color: AppColors.warn,
                              semanticLabel: '신청 때 금액과 지금 계산 금액이 다릅니다',
                            ),
                          ),
                        if (diff != 0)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.error_outline,
                              size: 16,
                              color: AppColors.danger,
                              semanticLabel: '입금액이 계산 금액과 다릅니다',
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          q.noPayment ? '무료' : won(q.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ],
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
    final free = q.noPayment;
    // 부분 참석자의 고른 날짜 (사람 id → "10-09(금) 10-10(토)").
    // 숙박비 별도 집회는 숙박한 밤도 붙인다 (전체 참석이어도 숙박은 사람마다 다르다).
    final days = {
      for (final l in q.lines)
        // 날짜 없는 집회는 날짜 대신 '참가' / '미참가'.
        if (l.dateless)
          l.person.id: l.stay
        else if (!l.full || l.separate)
          l.person.id: [
            if (!l.full) l.days.map(mdw).join(' '),
            if (l.separate)
              l.stayNights!.isEmpty
                  ? '숙박 안 함'
                  : '숙박 ${l.stayNights!.map(mdw).join(' ')}',
          ].join(' · '),
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
            RegStatusBadge(r.status, free: current.value?.freeFor(q) ?? false),
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
                        '${p.staff ? ' · 스탭' : ''}'
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
        if (!free) ...[
          const SectionTitle('입금'),
          const SizedBox(height: 6),
          kv('입금자명', r.depositorName),
        ],
        if (r.status == RegStatus.confirmed && !free) ...[
          kv('입금액', won(r.paid)),
          if (diffText(r.paid, q.total) case final d?) kv('차액', d),
          if (r.paidAt != null) kv('입금일', ymd(r.paidAt!)),
          kv('확인 방법', r.autoPaid ? '자동 (은행 내역)' : '수동'),
          for (final ref in paidRefs(r))
            kv('근거 거래', ref.split('|').join(' · ')),
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
                label: Text(free ? '확정' : '입금 확인'),
              )
            else
              OutlinedButton(
                onPressed: busy ? null : onRevert,
                child: Text(free ? '대기로 되돌리기' : '입금대기로 되돌리기'),
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

/// 입금액 − 계산 금액. 더 내면 경고색, 덜 내면 빨강.
class _DiffText extends StatelessWidget {
  const _DiffText(this.paid, this.due);
  final int paid, due;

  @override
  Widget build(BuildContext context) {
    final t = diffText(paid, due);
    if (t == null) return const SizedBox.shrink();
    return Text(
      t,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: paid > due ? AppColors.warnInk : AppColors.danger,
      ),
    );
  }
}

/// 입금 확인 방법 태그: 자동(은행 내역) / 수동.
class _PaidHow extends StatelessWidget {
  const _PaidHow(this.r);
  final Registration r;

  @override
  Widget build(BuildContext context) => Text(
    r.autoPaid ? '자동' : '수동',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: r.autoPaid ? AppColors.brand : AppColors.textMuted,
    ),
  );
}

/// 은행 내역 대조 미리보기. 확실한 건은 체크된 채, 확인이 필요한 건은 사유와 함께 체크 안 된 채로 보인다.
/// 같은 입금을 두 신청에 쓸 수 없게, 한 줄을 고르면 같은 입금을 쓰는 다른 줄은 막는다.
class BankPreview extends StatefulWidget {
  const BankPreview({
    super.key,
    required this.matches,
    required this.unmatched,
    required this.txCount,
  });
  final List<BankMatch> matches;
  final List<BankTx> unmatched;
  final int txCount;

  @override
  State<BankPreview> createState() => BankPreviewState();
}

class BankPreviewState extends State<BankPreview> {
  late final picked = {
    for (final m in widget.matches)
      if (m.issue == null) m,
  };

  String _at(DateTime t) =>
      '${mdw(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _row(BankMatch m) {
    final taken = picked.any((p) => p != m && p.tx == m.tx);
    final cell = TextStyle(fontSize: 13, fontFeatures: _tabular);
    final check = Checkbox(
      value: picked.contains(m),
      onChanged: taken
          ? null
          : (v) => setState(() => v == true ? picked.add(m) : picked.remove(m)),
    );
    // 휴대폰: 열 다섯 개(≈ 520px)가 안 들어간다. 이름·사유 / 금액 / 입금 일시를 줄로 쌓는다.
    if (windowSizeOf(context).isCompact) {
      const muted = TextStyle(fontSize: 12, color: AppColors.textMuted);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            check,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.reg.applicant,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (m.issue != null)
                    Text(
                      taken ? '${m.issue} · 다른 신청에 쓴 입금' : m.issue!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warnInk,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('받을 ${won(m.due)}', style: cell),
                      Text(
                        '입금 ${won(m.tx.amount)}',
                        style: cell.copyWith(fontWeight: FontWeight.w700),
                      ),
                      m.tx.amount == m.due
                          ? const Text(
                              '일치',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.ok,
                              ),
                            )
                          : _DiffText(m.tx.amount, m.due),
                    ],
                  ),
                  Text('${_at(m.tx.at)} · ${m.tx.name}', style: muted),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          check,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.reg.applicant,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (m.issue != null)
                  Text(
                    taken ? '${m.issue} · 다른 신청에 쓴 입금' : m.issue!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.warnInk,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(won(m.due), textAlign: TextAlign.right, style: cell),
          ),
          SizedBox(
            width: 96,
            child: Text(
              won(m.tx.amount),
              textAlign: TextAlign.right,
              style: cell.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 112,
            child: Align(
              alignment: Alignment.centerRight,
              child: m.tx.amount == m.due
                  ? const Text(
                      '일치',
                      style: TextStyle(fontSize: 12, color: AppColors.ok),
                    )
                  : _DiffText(m.tx.amount, m.due),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 150,
            child: Text(
              '${_at(m.tx.at)} · ${m.tx.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sure = [
      for (final m in widget.matches)
        if (m.issue == null) m,
    ];
    final check = [
      for (final m in widget.matches)
        if (m.issue != null) m,
    ];
    final head = const TextStyle(fontSize: 12, color: AppColors.textMuted);
    final compact = windowSizeOf(context).isCompact;
    return WideDialog(
      title: '은행 내역으로 입금 확인',
      width: 760,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: picked.isEmpty
              ? null
              : () => Navigator.pop(context, picked.toList()),
          child: Text('${picked.length}건 입금 확인'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '입금 ${widget.txCount}건 중 확실 ${sure.length} · 확인 필요 ${check.length} · '
            '맞는 신청 없음 ${widget.unmatched.length}. '
            '입금자명과 금액(계산 금액)을 같이 맞춰 봤습니다.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          // 휴대폰은 줄마다 금액을 글로 적으므로 열 머리글이 없다.
          if (!compact) ...[
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(child: Text('신청자', style: head)),
                SizedBox(
                  width: 96,
                  child: Text('받을 금액', textAlign: TextAlign.right, style: head),
                ),
                SizedBox(
                  width: 96,
                  child: Text('입금액', textAlign: TextAlign.right, style: head),
                ),
                SizedBox(
                  width: 112,
                  child: Text('차액', textAlign: TextAlign.right, style: head),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 150, child: Text('입금 일시 · 입금자', style: head)),
              ],
            ),
            const Divider(height: 12),
          ],
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (widget.matches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('입금대기 신청과 맞는 입금이 없습니다.'),
                  ),
                if (sure.isNotEmpty) SectionTitle('확실 ${sure.length}'),
                ...sure.map(_row),
                if (check.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionTitle(
                    '확인 필요 ${check.length}',
                    subtitle: '사유를 보고 맞으면 체크하세요.',
                  ),
                  ...check.map(_row),
                ],
                if (widget.unmatched.isNotEmpty)
                  ExpansionTile(
                    // 맞춘 게 없으면 왜 안 맞았는지 바로 보이게 펼쳐 둔다.
                    initiallyExpanded: widget.matches.isEmpty,
                    tilePadding: EdgeInsets.zero,
                    subtitle: const Text(
                      '입금자명이 신청자·입금자명과 다르거나, 신청한 날보다 앞선 거래입니다(앞선 거래는 대조하지 않습니다).',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    title: Text(
                      '맞는 신청이 없는 입금 ${widget.unmatched.length}건',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      for (final t in widget.unmatched)
                        ListTile(
                          dense: true,
                          title: Text(t.name.isEmpty ? '(입금자 없음)' : t.name),
                          subtitle: Text(_at(t.at)),
                          trailing: Text(
                            won(t.amount),
                            style: const TextStyle(fontFeatures: _tabular),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
