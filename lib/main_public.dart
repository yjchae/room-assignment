/// 신청 웹 (휴대폰 브라우저). 빌드: flutter build web -t lib/main_public.dart
/// 링크: <신청 웹 주소>?g=<집회id>
///
/// 운영자 쪽 코드(store.dart, screens/)는 가져오지 않는다 — 신청 웹 번들에 들어갈 이유가 없다.
/// 여기서 가져오는 파일(gathering · remote · theme · quote_table)은 dart:io 금지 (웹 빌드가 깨짐).
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'gathering.dart';
import 'remote.dart';
import 'theme.dart';
import 'widgets/quote_table.dart';

const _tabular = [FontFeature.tabularFigures()];
const _relations = ['배우자', '자녀', '부모', '형제자매', '기타'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Remote.init();
  } catch (e) {
    debugPrint('서버 준비 실패: $e');
  }
  runApp(PublicApp(gatheringId: Uri.base.queryParameters['g']));
}

class PublicApp extends StatelessWidget {
  const PublicApp({super.key, this.gatheringId});
  final String? gatheringId;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '집회 신청',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme().copyWith(visualDensity: VisualDensity.standard),
    home: GatheringPage(id: gatheringId),
  );
}

// ---------------------------------------------------------------------------
// 집회 페이지
// ---------------------------------------------------------------------------

class GatheringPage extends StatefulWidget {
  const GatheringPage({super.key, this.id});
  final String? id;

  @override
  State<GatheringPage> createState() => _GatheringPageState();
}

class _GatheringPageState extends State<GatheringPage> {
  late Future<Gathering> future = _load();

  Future<Gathering> _load() async {
    final id = widget.id?.trim() ?? '';
    if (id.isEmpty) {
      throw const RemoteError('잘못된 링크입니다. 받은 링크를 다시 확인하세요.');
    }
    final g = await remote.gathering(id);
    if (g == null) {
      throw const RemoteError('집회를 찾지 못했습니다. 받은 링크를 다시 확인하세요.');
    }
    return g;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Gathering>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) {
        return Scaffold(
          body: EmptyNotice(
            icon: Icons.link_off,
            text: errorText(snap.error!),
            action: OutlinedButton(
              onPressed: () => setState(() => future = _load()),
              child: const Text('다시 시도'),
            ),
          ),
        );
      }
      if (!snap.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return _GatheringView(snap.data!);
    },
  );
}

class _GatheringView extends StatelessWidget {
  const _GatheringView(this.g);
  final Gathering g;

  @override
  Widget build(BuildContext context) {
    final accepting = g.acceptingOn(DateTime.now());
    final bg = g.backgroundUrl;
    final address = g.address;
    return Scaffold(
      backgroundColor: bg == null ? AppColors.bg : AppColors.board,
      body: Stack(
        children: [
          if (bg != null) ...[
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Image.network(
                  bg,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: AppColors.text.withValues(alpha: 0.55)),
            ),
          ],
          SafeArea(
            child: _Narrow(
              children: [
                if (g.posterUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: Image.network(
                        g.posterUrl!,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                    ),
                  ),
                _Section(
                  children: [
                    Text(
                      g.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (g.themes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final t in g.themes) _Tag(t)],
                        ),
                      ),
                    const SizedBox(height: 14),
                    _Info(
                      Icons.event_outlined,
                      '${g.start.year}-${mdw(g.start)} ~ ${mdw(g.end)} · ${stayLabel(g.nights)}',
                    ),
                    if ((g.place ?? '').isNotEmpty ||
                        (address ?? '').isNotEmpty)
                      _Info(
                        Icons.place_outlined,
                        [g.place, address].whereType<String>().join('\n'),
                        action: (address ?? '').isEmpty
                            ? null
                            : TextButton(
                                onPressed: () => launchUrl(
                                  Uri.parse(
                                    'https://map.naver.com/p/search/${Uri.encodeComponent(address!)}',
                                  ),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Text('지도 보기'),
                              ),
                      ),
                    if ((g.notice ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          g.notice!,
                          style: const TextStyle(height: 1.6),
                        ),
                      ),
                  ],
                ),
                if (g.hasSchedule)
                  _Section(title: '일정', children: [_Schedule(g)]),
                if (!g.fee.isFree)
                  _Section(title: '회비', children: [_FeeTable(g)]),
                if (!g.fee.isFree && !g.bank.isEmpty)
                  _Section(title: '입금 계좌', children: [_BankBox(g.bank)]),
                _Section(
                  children: [
                    if (!accepting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '지금은 신청을 받지 않습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    FilledButton(
                      onPressed: accepting
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ApplyPage(gathering: g),
                              ),
                            )
                          : null,
                      child: const Text('신청하기'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LookupPage(gathering: g),
                        ),
                      ),
                      child: const Text('신청 조회 · 수정'),
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

/// 집회 기간의 날짜별 일정. 적어 둔 게 없는 날은 건너뛴다.
class _Schedule extends StatelessWidget {
  const _Schedule(this.g);
  final Gathering g;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final d in g.days)
        if (g.scheduleOn(d) case final items when items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mdw(d),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 4),
                for (final s in items)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            s.time,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFeatures: _tabular,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.title,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
    ],
  );
}

class _FeeTable extends StatelessWidget {
  const _FeeTable(this.g);
  final Gathering g;

  @override
  Widget build(BuildContext context) {
    final f = g.fee;
    final n = g.nights;
    final byAge = g.asks('birthYear');
    // 시작 나이가 높은 구분부터. 한 구분의 끝 나이 = 바로 위 구분의 시작 나이 − 1.
    final order = [...f.minAge.entries]
      ..sort((a, b) => b.value.compareTo(a.value));
    String ages(AgeGroup ag) {
      final i = order.indexWhere((e) => e.key == ag);
      final lo = f.minAge[ag] ?? 0;
      if (i <= 0) return '$lo세 이상';
      final hi = order[i - 1].value - 1;
      return hi <= lo ? '$lo세' : '$lo~$hi세';
    }

    // 전체 참석자가 실제로 내는 금액 (정액 또는 1박×박수, 전체참석 할인 반영).
    int fullOf(AgeGroup ag) =>
        (f.full[ag] ??
            (n > 0 ? (f.perNight[ag] ?? 0) * n : (f.dayOnly[ag] ?? 0))) *
        (100 - f.fullDiscountPct.clamp(0, 100)) ~/
        100;
    String money(int v) => v == 0 ? '무료' : won(v);
    Widget cell(String t, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Text(
        t,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: head ? 12 : 13,
          color: head ? AppColors.textMuted : AppColors.text,
          fontWeight: head ? FontWeight.w500 : FontWeight.w600,
          fontFeatures: _tabular,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const Text(
                  '구분',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                cell('전체 참석', head: true),
                if (n > 0) cell('1박', head: true),
                cell('당일', head: true),
              ],
            ),
            // 출생연도를 안 받으면 모두 성인 금액이라 성인 줄만.
            for (final ag in byAge ? AgeGroup.values : [AgeGroup.adult])
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ag.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (byAge)
                          Text(
                            ages(ag),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  cell(money(fullOf(ag))),
                  if (n > 0) cell(money(f.perNight[ag] ?? 0)),
                  cell(money(f.dayOnly[ag] ?? 0)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final line in [
          if (byAge) '나이는 ${g.start.year}년 − 출생연도로 계산합니다.',
          if (byAge && !g.requires('birthYear')) '출생연도를 비워 두면 성인 금액으로 계산합니다.',
          if (f.fullDiscountPct > 0)
            '전체 참석 금액은 전체 참석 할인 ${f.fullDiscountPct}%가 반영된 금액입니다.',
          '부분 참석 금액은 전체 참석 금액을 넘지 않습니다.',
          for (final e in f.early)
            '사전등록 할인: ${mdw(daysBefore(g.start, e.fromDays))} ~ '
                '${mdw(daysBefore(g.start, e.toDays))} 신청 시 ${e.pct}%',
          if (f.perRegistration > 0)
            '가족(신청 1건)당 ${won(f.perRegistration)}이 더해집니다.',
        ])
          Text(
            '· $line',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.6,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 신청서 (새 신청 / 수정)
// ---------------------------------------------------------------------------

/// 신청서의 사람 한 명 입력칸.
class _PersonForm {
  _PersonForm({Person? p, this.applicant = false, _PersonForm? copyFrom})
    : id = p?.id ?? newPersonId(),
      phone = p?.phone,
      name = TextEditingController(text: p?.name ?? ''),
      birth = TextEditingController(
        text: p == null || p.birthYear == 0 ? '' : '${p.birthYear}',
      ),
      // 셀·존은 가족이라도 다를 수 있어 동반자는 빈칸으로 시작한다.
      cell = TextEditingController(text: p?.cell ?? ''),
      zone = TextEditingController(text: p?.zone ?? ''),
      church = TextEditingController(text: p?.church ?? ''),
      gender = p?.gender,
      minister = p?.minister ?? false,
      relation = p?.relation ?? (applicant ? '본인' : '자녀') {
    if (p != null) {
      for (final e in p.extra.entries) {
        extras[e.key] = TextEditingController(text: e.value);
      }
    } else if (copyFrom != null) {
      for (final e in copyFrom.extras.entries) {
        extras[e.key] = TextEditingController(text: e.value.text);
      }
    }
  }

  /// 사람 id 는 수정해도 그대로 — 관리자 앱이 이 id 로 참석자를 맞춘다.
  final String id;
  final bool applicant;
  final String? phone;
  final TextEditingController name, birth, cell, zone, church;
  final extras = <String, TextEditingController>{};
  String? gender;
  bool minister;
  String relation;

  /// 참석하는 날. null = 전체 참석.
  Set<DateTime>? days;

  bool get full => days == null;

  TextEditingController extra(String field) =>
      extras.putIfAbsent(field, TextEditingController.new);

  int? get birthYear {
    final n = int.tryParse(birth.text.trim());
    return n == null || n < 1900 || n > DateTime.now().year ? null : n;
  }

  /// 금액 계산·제출용. 출생연도가 아직 없거나 틀리면 null.
  /// 운영자가 출생연도를 안 받거나, 선택 항목인데 비워 두면 0 = 모름(성인 금액).
  Person? toPerson(Gathering g, {String? phone}) {
    final skip =
        !g.asks('birthYear') ||
        (!g.requires('birthYear') && birth.text.trim().isEmpty);
    final y = skip ? 0 : birthYear;
    if (y == null) return null;
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return Person(
      id: id,
      name: name.text.trim(),
      // 성별은 금액과 무관. 받는 집회면 제출 전에 따로 검사하고, 안 받으면 '' = 모름.
      gender: gender ?? '',
      birthYear: y,
      relation: relation,
      days: days == null ? null : ([...days!]..sort()),
      phone: phone ?? this.phone,
      cell: t(cell),
      zone: t(zone),
      minister: g.asks('minister') && minister,
      church: g.asks('minister') && minister ? t(church) : null,
      extra: {
        for (final e in extras.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
    );
  }
}

class ApplyPage extends StatefulWidget {
  const ApplyPage({
    super.key,
    required this.gathering,
    this.editing,
    this.phone,
    this.pin,
    this.admin = false,
  });
  final Gathering gathering;

  /// 수정이면 기존 신청과, 조회에 쓴 휴대폰·PIN.
  final Registration? editing;
  final String? phone, pin;

  /// 운영자 앱의 [신청 추가] (전화·현장 접수). 동의 칸이 없고, PIN 은 미리 채워 보여 주고,
  /// 신청을 받지 않는 중에도 넣을 수 있다. 끝나면 신청 id 를 들고 닫힌다.
  final bool admin;

  @override
  State<ApplyPage> createState() => _ApplyPageState();
}

class _ApplyPageState extends State<ApplyPage> {
  final formKey = GlobalKey<FormState>();
  late final List<_PersonForm> forms;
  final phone = TextEditingController();
  final pin = TextEditingController();
  final depositor = TextEditingController();
  final memo = TextEditingController();
  bool consent = false, tried = false, busy = false;
  String? serverError;

  Gathering get g => widget.gathering;
  bool get editing => widget.editing != null;
  bool get free => g.fee.isFree;

  /// 수정할 때도 처음 신청한 날 기준으로 계산한다 (얼리버드 유지).
  DateTime get appliedAt => widget.editing?.createdAt ?? DateTime.now();

  /// 수정 중인 신청에 운영자가 준 지정 할인.
  Discount get discount => widget.editing?.discount ?? Discount.none;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    forms = r == null
        ? [_PersonForm(applicant: true)]
        : [
            for (final (i, p) in r.people.indexed)
              _PersonForm(p: p, applicant: i == 0),
          ];
    for (final f in forms) {
      f.birth.addListener(_changed);
    }
    if (widget.admin) {
      pin.text = '${math.Random.secure().nextInt(10000)}'.padLeft(4, '0');
    }
    if (r != null) {
      // 예전 형식(도착·출발일)이나 기간이 바뀐 신청도 날짜 체크로 옮긴다. 모든 날이면 전체 참석.
      for (final (i, p) in r.people.indexed) {
        final d = p.daysIn(g.start, g.end);
        if (d.length < g.days.length) forms[i].days = d.toSet();
      }
      depositor.text = r.depositor ?? '';
      memo.text = r.memo ?? '';
    }
  }

  void _changed() => setState(() {});

  List<Person> get _people => [for (final f in forms) ?f.toPerson(g)];

  void _addCompanion() => setState(
    () => forms.add(
      _PersonForm(copyFrom: forms.first)..birth.addListener(_changed),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final q = g.quoteFor(_people, appliedAt, discount: discount);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.admin
              ? '신청 추가 (운영자 접수)'
              : editing
              ? '신청 수정'
              : '신청하기',
        ),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: Form(
        key: formKey,
        autovalidateMode: tried
            ? AutovalidateMode.always
            : AutovalidateMode.disabled,
        child: _Narrow(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                g.name,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
            for (final (i, f) in forms.indexed) _personCard(i, f, q),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('동반 참석자 추가 (가족 등)'),
              onPressed: forms.length >= 20 ? null : _addCompanion,
            ),
            const SizedBox(height: 12),
            _Section(
              title: free ? '연락처' : '연락처 · 입금',
              children: [
                if (!editing) ...[
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '휴대폰번호 *',
                      hintText: '010-1234-5678',
                    ),
                    validator: (v) =>
                        validPhone(v ?? '') ? null : '010으로 시작하는 휴대폰번호를 입력하세요',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: !widget.admin,
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: '조회용 PIN (숫자 4자리) *',
                      helperText: widget.admin
                          ? '신청자에게 알려 주세요. 휴대폰번호와 함께 조회·수정할 때 씁니다.'
                          : '나중에 휴대폰번호와 함께 신청을 조회·수정할 때 씁니다.',
                    ),
                    validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '')
                        ? null
                        : '숫자 4자리를 입력하세요',
                  ),
                  const SizedBox(height: 4),
                ],
                if (!free)
                  TextFormField(
                    controller: depositor,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: '입금자명',
                      hintText: '비워두면 신청자 이름',
                      helperText: '신청자와 다른 이름으로 입금하면 적어 주세요.',
                    ),
                  ),
                TextFormField(
                  controller: memo,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '메모 (선택)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
            if (!editing && !widget.admin) _Section(children: [_consent()]),
            if (serverError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  serverError!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _TotalBar(
        q: q,
        free: free,
        busy: busy,
        label: editing
            ? '수정 저장'
            : widget.admin
            ? '신청 추가'
            : '신청하기',
        onSubmit: _submit,
      ),
    );
  }

  Widget _personCard(int i, _PersonForm f, Quote q) {
    final line = q.lines.where((l) => l.person.id == f.id).firstOrNull;
    return _Section(
      title: f.applicant ? '신청자' : '동반 참석자 $i',
      trailing: f.applicant
          ? null
          : IconButton(
              tooltip: '이 사람 빼기',
              icon: const Icon(Icons.close),
              onPressed: () => setState(
                () => forms.removeAt(i).birth.removeListener(_changed),
              ),
            ),
      children: [
        TextFormField(
          controller: f.name,
          decoration: const InputDecoration(labelText: '이름 *'),
          validator: (v) => (v ?? '').trim().isEmpty ? '이름을 입력하세요' : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (g.asks('birthYear')) ...[
              Expanded(
                child: TextFormField(
                  controller: f.birth,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: _label('출생연도', 'birthYear'),
                    hintText: '1985',
                    counterText: '',
                  ),
                  validator: (_) =>
                      f.toPerson(g) == null ? '4자리 연도로 입력하세요' : null,
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (g.asks('gender'))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'M', label: Text('남')),
                      ButtonSegment(value: 'F', label: Text('여')),
                    ],
                    selected: {?f.gender},
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => f.gender = s.firstOrNull),
                  ),
                  if (tried && f.gender == null && g.requires('gender'))
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        '성별을 고르세요',
                        style: TextStyle(fontSize: 12, color: AppColors.danger),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (!f.applicant) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _relations.contains(f.relation) ? f.relation : '기타',
            isExpanded: true,
            decoration: const InputDecoration(labelText: '신청자와의 관계'),
            items: [
              for (final r in _relations)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) => f.relation = v ?? '기타',
          ),
        ],
        if (g.asks('cell') || g.asks('zone')) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (g.asks('cell'))
                Expanded(
                  child: TextFormField(
                    controller: f.cell,
                    decoration: InputDecoration(labelText: _label('셀', 'cell')),
                    validator: (v) => _need('cell', v, '셀을 입력하세요'),
                  ),
                ),
              if (g.asks('cell') && g.asks('zone')) const SizedBox(width: 12),
              if (g.asks('zone'))
                Expanded(
                  child: TextFormField(
                    controller: f.zone,
                    decoration: InputDecoration(labelText: _label('존', 'zone')),
                    validator: (v) => _need('zone', v, '존을 입력하세요'),
                  ),
                ),
            ],
          ),
        ],
        if (g.asks('minister'))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('사역자입니다'),
            value: f.minister,
            onChanged: (v) => setState(() => f.minister = v ?? false),
          ),
        if (g.asks('minister') && f.minister)
          TextFormField(
            controller: f.church,
            decoration: const InputDecoration(labelText: '교회 이름 *'),
            validator: (v) => (v ?? '').trim().isEmpty ? '교회 이름을 입력하세요' : null,
          ),
        for (final field in g.formFields)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              controller: f.extra(field),
              decoration: InputDecoration(labelText: field),
            ),
          ),
        const SizedBox(height: 4),
        _schedule(f),
        if (line != null && !free)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${line.group.label} · ${line.stay} · ${won(line.amount)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.brand,
              ),
            ),
          ),
      ],
    );
  }

  /// 운영자가 필수로 정한 기본 항목은 이름 뒤에 * 를 붙인다.
  String _label(String text, String field) =>
      g.requires(field) ? '$text *' : text;

  String? _need(String field, String? v, String error) =>
      g.requires(field) && (v ?? '').trim().isEmpty ? error : null;

  Widget _schedule(_PersonForm f) {
    final days = g.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('전체 참석'),
          subtitle: Text(
            '${mdw(g.start)} ~ ${mdw(g.end)} · ${stayLabel(g.nights)}',
          ),
          value: f.full,
          onChanged: g.nights == 0
              ? null
              : (v) => setState(() => f.days = v ? null : {}),
        ),
        if (!f.full) ...[
          const Text(
            '참석하는 날을 모두 고르세요. 이어서 고른 날 사이는 숙박으로 봅니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          for (final d in days)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(mdw(d)),
              value: f.days!.contains(d),
              onChanged: (v) => setState(() {
                if (v == true) {
                  f.days!.add(d);
                } else {
                  f.days!.remove(d);
                }
              }),
            ),
          if (tried && f.days!.isEmpty)
            const Text(
              '참석하는 날을 하루 이상 고르세요',
              style: TextStyle(fontSize: 12, color: AppColors.danger),
            ),
        ],
      ],
    );
  }

  Widget _consent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: consent,
        onChanged: (v) => setState(() => consent = v == true),
        title: const Text(
          '개인정보 수집·이용에 동의합니다 (필수)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      const Text(
        '수집 항목: 이름, 성별, 출생연도, 휴대폰번호, 소속(셀·존 등)\n'
        '이용 목적: 집회 운영, 회비 확인, 숙소 배정\n'
        '보유 기간: 집회 종료 후 3개월까지 보관 후 삭제\n'
        '동의하지 않으면 신청할 수 없습니다.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
      ),
      if (tried && !consent)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '동의가 필요합니다.',
            style: TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ),
    ],
  );

  Future<void> _submit() async {
    setState(() {
      tried = true;
      serverError = null;
    });
    final formOk = formKey.currentState!.validate();
    final genderOk =
        !g.requires('gender') || forms.every((f) => f.gender != null);
    final daysOk = forms.every((f) => f.full || f.days!.isNotEmpty);
    if (!formOk ||
        !genderOk ||
        !daysOk ||
        (!editing && !widget.admin && !consent)) {
      setState(() => serverError = '빨간 표시된 칸을 확인하세요.');
      return;
    }
    final people = [
      for (final (i, f) in forms.indexed)
        f.toPerson(
          g,
          phone: i == 0 && !editing ? digitsOnly(phone.text) : null,
        )!,
    ];
    final q = g.quoteFor(people, appliedAt, discount: discount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(editing ? '이대로 수정할까요?' : '이대로 신청할까요?'),
        content: free
            ? null
            : SizedBox(
                width: 400,
                child: SingleChildScrollView(child: QuoteTable(q)),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('다시 보기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(editing ? '수정' : '신청'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    final dep = depositor.text.trim().isEmpty ? null : depositor.text.trim();
    final m = memo.text.trim().isEmpty ? null : memo.text.trim();
    try {
      if (widget.admin) {
        final id = await remote.adminSubmit(
          g.id,
          phone: phone.text,
          pin: pin.text,
          people: people,
          depositor: dep,
          memo: m,
          quoted: q.beforeDiscount,
        );
        if (mounted) Navigator.pop(context, id);
      } else if (!editing) {
        await remote.submit(
          g.id,
          phone: phone.text,
          pin: pin.text,
          people: people,
          depositor: dep,
          memo: m,
          quoted: q.beforeDiscount,
        );
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DonePage(
              gathering: g,
              quote: q,
              depositor: dep ?? people.first.name,
            ),
          ),
        );
      } else {
        final r = await remote.updateMine(
          g.id,
          widget.phone!,
          widget.pin!,
          people: people,
          depositor: dep,
          memo: m,
          quoted: q.beforeDiscount,
        );
        if (r == null) {
          throw const RemoteError('휴대폰번호나 PIN이 맞지 않습니다. 조회부터 다시 해 주세요.');
        }
        if (mounted) Navigator.pop(context, r);
      }
    } catch (e) {
      if (mounted) setState(() => serverError = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// 신청서 아래 고정 줄: 인원 요약 · 합계 · 제출 버튼. 합계를 누르면 내역.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.q,
    required this.free,
    required this.busy,
    required this.label,
    required this.onSubmit,
  });
  final Quote q;

  /// 무료 집회 — 금액 없이 인원 요약만.
  final bool free;
  final bool busy;
  final String label;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            if (free)
              Expanded(
                child: Text(
                  q.summary,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              Expanded(
                child: InkWell(
                  onTap: q.lines.isEmpty
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                            child: QuoteTable(q),
                          ),
                        ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.lines.isEmpty ? '출생연도를 넣으면 금액이 계산됩니다' : q.summary,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            won(q.total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFeatures: _tabular,
                            ),
                          ),
                          if (q.lines.isNotEmpty)
                            const Icon(
                              Icons.expand_less,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: Text(busy ? '보내는 중…' : label),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 완료 · 조회
// ---------------------------------------------------------------------------

/// 사역자를 체크한 신청자에게만 보이는 안내 (문구는 집회 설정에서 바꾼다).
Widget _ministerNotice(String text) => _Section(
  children: [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info, size: 20, color: AppColors.brand),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  ],
);

class DonePage extends StatelessWidget {
  const DonePage({
    super.key,
    required this.gathering,
    required this.quote,
    required this.depositor,
  });
  final Gathering gathering;
  final Quote quote;
  final String depositor;

  @override
  Widget build(BuildContext context) {
    final free = gathering.fee.isFree;
    return Scaffold(
      appBar: AppBar(
        title: const Text('신청 완료'),
        automaticallyImplyLeading: false,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: _Narrow(
        children: [
          _Section(
            children: [
              const Icon(Icons.check_circle, size: 48, color: AppColors.ok),
              const SizedBox(height: 8),
              const Text(
                '신청이 접수되었습니다',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(
                free ? '담당자가 확인하면 신청이 확정됩니다.' : '입금이 확인되면 신청이 확정됩니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (!free) ...[const SizedBox(height: 16), QuoteTable(quote)],
            ],
          ),
          if (gathering.ministerNoticeFor(quote.lines.map((l) => l.person)))
            _ministerNotice(gathering.ministerNotice),
          if (!free && !gathering.bank.isEmpty)
            _Section(
              title: '입금 계좌',
              children: [_BankBox(gathering.bank, depositor: depositor)],
            ),
          _Section(
            children: [
              Text(
                '휴대폰번호와 PIN으로 [신청 조회]에서 ${free ? '확정' : '입금 확인'} 여부를 볼 수 있습니다.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('집회 페이지로'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LookupPage extends StatefulWidget {
  const LookupPage({super.key, required this.gathering});
  final Gathering gathering;

  @override
  State<LookupPage> createState() => _LookupPageState();
}

class _LookupPageState extends State<LookupPage> {
  final phone = TextEditingController();
  final pin = TextEditingController();
  Registration? reg;
  String? error;
  bool busy = false;

  Gathering get g => widget.gathering;

  Future<void> _lookup() async {
    if (!validPhone(phone.text) || !RegExp(r'^\d{4}$').hasMatch(pin.text)) {
      setState(() => error = '휴대폰번호와 PIN 4자리를 입력하세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await remote.lookup(g.id, phone.text, pin.text);
      setState(() {
        reg = r;
        if (r == null) error = '휴대폰번호나 PIN이 맞지 않습니다. 5번 틀리면 30분간 잠깁니다.';
      });
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit() async {
    final r = await Navigator.push<Registration>(
      context,
      MaterialPageRoute(
        builder: (_) => ApplyPage(
          gathering: g,
          editing: reg,
          phone: phone.text,
          pin: pin.text,
        ),
      ),
    );
    if (r != null) setState(() => reg = r);
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: '신청 취소',
      body: '신청을 취소합니다. 다시 참석하려면 새로 신청해야 합니다.',
      action: '신청 취소',
      danger: true,
    );
    if (!ok) return;
    setState(() => busy = true);
    try {
      final r = await remote.cancelMine(g.id, phone.text, pin.text);
      setState(() => reg = r ?? reg);
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('신청 조회'),
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
    ),
    body: _Narrow(children: reg == null ? _form() : _view(reg!)),
  );

  List<Widget> _form() => [
    _Section(
      children: [
        Text(g.name, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: '휴대폰번호'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'PIN (숫자 4자리)'),
          onSubmitted: (_) => busy ? null : _lookup(),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        FilledButton(
          onPressed: busy ? null : _lookup,
          child: Text(busy ? '조회 중…' : '조회'),
        ),
        const SizedBox(height: 8),
        const Text(
          'PIN을 잊었으면 담당자에게 문의하세요.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ),
  ];

  List<Widget> _view(Registration r) {
    final q = g.quoteFor(r.people, r.createdAt, discount: r.discount);
    final pending = r.status == RegStatus.pending;
    final canEdit = pending && g.acceptingOn(DateTime.now());
    final free = g.fee.isFree;
    return [
      _Section(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.applicant,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RegStatusBadge(r.status, free: free),
            ],
          ),
          const SizedBox(height: 6),
          Text(switch (r.status) {
            RegStatus.pending when free => '담당자 확인을 기다리고 있습니다.',
            RegStatus.pending => '입금을 기다리고 있습니다. 아래 계좌로 입금해 주세요.',
            RegStatus.confirmed when free => '신청이 확정되었습니다.',
            RegStatus.confirmed => '입금이 확인되어 신청이 확정되었습니다.',
            RegStatus.cancelled => '취소된 신청입니다.',
          }, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          if (!free) ...[const SizedBox(height: 16), QuoteTable(q)],
          if (r.status == RegStatus.confirmed && !free)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '확인된 입금액 ${won(r.paid)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ok,
                ),
              ),
            ),
        ],
      ),
      if (g.isHomestay && r.status == RegStatus.confirmed)
        _Section(
          title: '우리 집에 배정된 참석자',
          trailing: r.assigned.isEmpty
              ? null
              : Text(
                  '${r.assigned.length}명',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
          children: [
            if (r.assigned.isEmpty)
              const Text(
                '아직 배정 전입니다. 배정되면 여기에 표시됩니다.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              )
            else
              for (final a in r.assigned) _AssignedRow(a),
          ],
        ),
      if (r.status != RegStatus.cancelled && g.ministerNoticeFor(r.people))
        _ministerNotice(g.ministerNotice),
      if (pending && !free && !g.bank.isEmpty)
        _Section(
          title: '입금 계좌',
          children: [_BankBox(g.bank, depositor: r.depositorName)],
        ),
      if (pending)
        _Section(
          children: [
            if (canEdit)
              FilledButton(
                onPressed: busy ? null : _edit,
                child: const Text('신청 내용 수정'),
              )
            else
              const Text(
                '신청이 마감되어 수정할 수 없습니다. 변경은 담당자에게 문의하세요.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              onPressed: busy ? null : _cancel,
              child: const Text('신청 취소'),
            ),
          ],
        ),
      if (r.status == RegStatus.confirmed)
        const _Section(
          children: [
            Text(
              '변경이 필요하면 담당자에게 문의하세요.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(error!, style: const TextStyle(color: AppColors.danger)),
        ),
      TextButton(
        onPressed: () => setState(() {
          reg = null;
          pin.clear();
        }),
        child: const Text('다른 번호로 조회'),
      ),
    ];
  }
}

/// 우리 집에 배정된 참석자 한 줄. 연락처는 눌러서 바로 걸 수 있다.
class _AssignedRow extends StatelessWidget {
  const _AssignedRow(this.a);
  final AssignedGuest a;

  @override
  Widget build(BuildContext context) {
    final sub = [
      switch (a.gender) {
        'M' => '남',
        'F' => '여',
        _ => null,
      },
      if (a.age > 0) '${a.age}세',
      a.cell,
      a.zone,
    ].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (a.phone != null)
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('tel:${digitsOnly(a.phone!)}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.call_outlined, size: 16),
              label: Text(
                fmtPhone(a.phone!),
                style: const TextStyle(fontFeatures: _tabular),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 공용 조각
// ---------------------------------------------------------------------------

/// 휴대폰 폭 기준 가운데 한 줄 레이아웃.
class _Narrow extends StatelessWidget {
  const _Narrow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: children,
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({this.title, this.trailing, required this.children});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              SectionTitle(title!, trailing: trailing),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '#$text',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.brand,
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text, {this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
        ?action,
      ],
    ),
  );
}

class _BankBox extends StatelessWidget {
  const _BankBox(this.bank, {this.depositor});
  final Bank bank;
  final String? depositor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.control),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${bank.bank} ${bank.account}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tabular,
                ),
              ),
              if (bank.holder.isNotEmpty)
                Text(
                  '예금주 ${bank.holder}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              if (depositor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '입금자명: $depositor',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand,
                    ),
                  ),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('복사'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: bank.account));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('계좌번호를 복사했습니다.')));
          },
        ),
      ],
    ),
  );
}
