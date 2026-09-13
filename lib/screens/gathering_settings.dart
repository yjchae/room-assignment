import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../gathering.dart';
import '../main.dart';
import '../models.dart';
import '../remote.dart';
import '../theme.dart';
import 'attendees.dart' show addCustomFieldDialog;
import 'gatherings.dart';

/// 집회 설정 (서버). 저장하면 이 PC 의 방배정 파일 이름·날짜·항목도 같이 바뀐다.
class GatheringSettingsScreen extends StatefulWidget {
  const GatheringSettingsScreen({super.key});

  @override
  State<GatheringSettingsScreen> createState() =>
      _GatheringSettingsScreenState();
}

/// 사전등록 할인 한 줄의 입력칸.
class _Early {
  _Early(int fromDays, int toDays, int pct)
    : fromDays = TextEditingController(text: '$fromDays'),
      toDays = TextEditingController(text: '$toDays'),
      pct = TextEditingController(text: '$pct');
  final TextEditingController fromDays, toDays, pct;
}

/// 회비표의 열: 키 → 머리글.
const _feeCols = {
  'minAge': '시작 나이',
  'full': '전체 참석',
  'perNight': '1박당 (부분 참석)',
  'dayOnly': '당일',
};

class _GatheringSettingsScreenState extends State<GatheringSettingsScreen> {
  /// 고치는 중인 사본. 저장 전까지 서버·[current] 와 다를 수 있다.
  Gathering? g;

  final name = TextEditingController();
  final place = TextEditingController();
  final address = TextEditingController();
  final notice = TextEditingController();
  final bank = TextEditingController();
  final account = TextEditingController();
  final holder = TextEditingController();
  final perReg = TextEditingController();
  final fullPct = TextEditingController();
  final themeInput = TextEditingController();

  /// '열키:구분' → 입력칸. 예: 'full:adult'
  final fee = <String, TextEditingController>{};
  final early = <_Early>[];

  List<String> errors = [];
  bool saving = false;
  ImageKind? uploading;
  String? imageInfo;

  @override
  void initState() {
    super.initState();
    final c = current.value;
    if (c != null) _fill(c.copy());
  }

  void _fill(Gathering x) {
    g = x;
    name.text = x.name;
    place.text = x.place ?? '';
    address.text = x.address ?? '';
    notice.text = x.notice ?? '';
    bank.text = x.bank.bank;
    account.text = x.bank.account;
    holder.text = x.bank.holder;
    perReg.text = x.fee.perRegistration == 0 ? '' : '${x.fee.perRegistration}';
    fullPct.text = x.fee.fullDiscountPct == 0 ? '' : '${x.fee.fullDiscountPct}';
    for (final ag in AgeGroup.values) {
      fee['minAge:${ag.name}'] = TextEditingController(
        text: '${x.fee.minAge[ag] ?? FeeRule.defaultMinAge[ag]}',
      );
      fee['full:${ag.name}'] = TextEditingController(
        text: x.fee.full[ag]?.toString() ?? '',
      );
      fee['perNight:${ag.name}'] = TextEditingController(
        text: x.fee.perNight[ag]?.toString() ?? '',
      );
      fee['dayOnly:${ag.name}'] = TextEditingController(
        text: x.fee.dayOnly[ag]?.toString() ?? '',
      );
    }
    early
      ..clear()
      ..addAll(x.fee.early.map((e) => _Early(e.fromDays, e.toDays, e.pct)));
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// 입력칸 → [g]. 문제가 있으면 문장 목록.
  List<String> _collect() {
    final x = g!;
    final errs = <String>[];

    int? number(String text, String label, {int? max}) {
      final t = text.replaceAll(',', '').trim();
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      if (n == null || n < 0 || (max != null && n > max)) {
        errs.add(
          max == null
              ? '$label: 0 이상의 숫자로 입력하세요.'
              : '$label: 0~$max 사이 숫자로 입력하세요.',
        );
        return null;
      }
      return n;
    }

    Map<AgeGroup, int> column(String col) => {
      for (final ag in AgeGroup.values)
        ag: ?number(
          fee['$col:${ag.name}']!.text,
          '${_feeCols[col]} · ${ag.label}',
        ),
    };

    x.name = name.text.trim();
    if (x.name.isEmpty) errs.add('집회 이름을 입력하세요.');
    if (x.end.isBefore(x.start)) errs.add('종료일이 시작일보다 빠릅니다.');
    x.place = _opt(place);
    x.address = _opt(address);
    x.notice = _opt(notice);
    x.bank = Bank(
      bank: bank.text.trim(),
      account: account.text.trim(),
      holder: holder.text.trim(),
    );

    final minAge = column('minAge');
    for (final ag in AgeGroup.values) {
      if (fee['minAge:${ag.name}']!.text.trim().isEmpty) {
        errs.add('시작 나이 · ${ag.label}: 비워둘 수 없습니다.');
      }
    }
    final es = <EarlyDiscount>[];
    for (final (i, e) in early.indexed) {
      final label = '사전등록 할인 ${i + 1}';
      var from = number(e.fromDays.text, label, max: 3650);
      var to = number(e.toDays.text, label, max: 3650);
      final pct = number(e.pct.text, label, max: 100);
      if (from == null || to == null || pct == null) {
        errs.add('$label: 며칠 전부터·까지와 할인율을 모두 입력하세요.');
        continue;
      }
      if (from < to) (from, to) = (to, from);
      es.add((fromDays: from, toDays: to, pct: pct));
    }
    x.fee = FeeRule(
      full: column('full'),
      perNight: column('perNight'),
      dayOnly: column('dayOnly'),
      minAge: {...FeeRule.defaultMinAge, ...minAge},
      perRegistration: number(perReg.text, '가족당 금액') ?? 0,
      fullDiscountPct: number(fullPct.text, '전체 참석 할인율', max: 100) ?? 0,
      early: es,
    );
    if (x.open && x.bank.isEmpty) errs.add('신청을 받으려면 입금 계좌를 입력하세요.');
    return errs;
  }

  Future<void> _save() async {
    final errs = _collect();
    setState(() => errors = errs);
    if (errs.isNotEmpty) return;
    if (!await ensureAdmin(context)) return;
    setState(() => saving = true);
    try {
      g!.formFields = [...store.event.customFields];
      final saved = await remote.saveGathering(g!);
      current.value = saved;
      store.applyGathering(saved);
      g = saved.copy();
      _snack('저장했습니다. 신청 웹에 바로 반영됩니다.');
    } catch (e) {
      setState(() => errors = [errorText(e)]);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _setUrl(Gathering x, ImageKind k, String? url) =>
      k == ImageKind.poster ? x.posterUrl = url : x.backgroundUrl = url;

  String? _urlOf(Gathering x, ImageKind k) =>
      k == ImageKind.poster ? x.posterUrl : x.backgroundUrl;

  /// 이미지는 고르는 즉시 줄여서 올리고 그 칸만 저장한다 (다른 칸의 저장 안 한 수정은 그대로).
  Future<void> _pickImage(ImageKind kind) async {
    if (!await ensureAdmin(context)) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return;
    setState(() {
      uploading = kind;
      imageInfo = null;
      errors = [];
    });
    try {
      final raw = await file.readAsBytes();
      if (raw.length > 20 * 1024 * 1024) {
        throw const RemoteError('20MB 이하 이미지만 올릴 수 있습니다.');
      }
      final jpeg = await shrinkImageInBackground(raw, kind);
      if (jpeg == null) {
        throw const RemoteError(
          '이미지를 읽지 못했습니다. JPG 또는 PNG로 저장해서 올려주세요. (아이폰 HEIC는 안 됩니다)',
        );
      }
      await _saveImage(kind, await remote.uploadImage(g!.id, kind, jpeg));
      imageInfo =
          '${kind.label}: ${_size(raw.length)} → ${_size(jpeg.length)}로 줄여서 올렸습니다.';
    } catch (e) {
      errors = [errorText(e)];
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _clearImage(ImageKind kind) async {
    setState(() => uploading = kind);
    try {
      await _saveImage(kind, null);
    } catch (e) {
      errors = [errorText(e)];
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _saveImage(ImageKind kind, String? url) async {
    final server = current.value!.copy();
    final old = _urlOf(server, kind);
    _setUrl(server, kind, url);
    final saved = await remote.saveGathering(server);
    current.value = saved;
    _setUrl(g!, kind, url);
    await remote.deleteImage(old);
  }

  Future<void> _delete(Gathering cur) async {
    if (!await ensureAdmin(context) || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: '"${cur.name}" 삭제',
      body:
          '서버의 집회 설정과 신청 내역이 모두 지워지고 되돌릴 수 없습니다.\n'
          '이 PC의 방배정 파일은 남습니다.',
      action: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await remote.deleteGathering(cur);
      if (mounted) await Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => errors = [errorText(e)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = current.value;
    if (cur == null || g == null) {
      return const EmptyNotice(
        icon: Icons.cloud_off_outlined,
        text: '서버에 연결된 집회만 설정할 수 있습니다.\n인터넷 연결을 확인하고 집회 목록에서 다시 열어 주세요.',
      );
    }
    final x = g!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    const SectionTitle(
                      '집회 설정',
                      subtitle: '[저장]해야 신청 웹에 반영됩니다. 이미지는 고르는 즉시 올라갑니다.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('신청 링크 복사'),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: applyLink(cur.id)),
                            );
                            _snack('신청 링크를 복사했습니다. 카톡 공지에 붙여넣으세요.');
                          },
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: Text(saving ? '저장 중…' : '저장'),
                          onPressed: saving ? null : _save,
                        ),
                      ],
                    ),
                  ],
                ),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      e,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                if (imageInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      imageInfo!,
                      style: const TextStyle(color: AppColors.ok),
                    ),
                  ),
                const SizedBox(height: 16),
                _card('기본 정보', [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '집회 이름 *'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in x.themes)
                        InputChip(
                          label: Text(t),
                          onDeleted: () => setState(() => x.themes.remove(t)),
                        ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: themeInput,
                          decoration: const InputDecoration(
                            labelText: '주제 추가',
                            hintText: '입력 후 Enter',
                          ),
                          onSubmitted: (v) {
                            final t = v.trim();
                            if (t.isNotEmpty && !x.themes.contains(t)) {
                              setState(() => x.themes.add(t));
                            }
                            themeInput.clear();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _dateButton('시작', x.start, (d) {
                        x.start = d;
                        if (x.end.isBefore(d)) x.end = d;
                      }),
                      _dateButton('종료', x.end, (d) => x.end = d),
                      Text(
                        stayLabel(x.nights),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: place,
                          decoration: const InputDecoration(labelText: '장소명'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: address,
                          decoration: const InputDecoration(
                            labelText: '주소 (신청 웹의 [지도 보기]에 씁니다)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notice,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '안내 문구',
                      hintText: '준비물, 문의처 등',
                      alignLabelWithHint: true,
                    ),
                  ),
                ]),
                _card('이미지', [
                  Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    children: [
                      _imageSlot(ImageKind.poster, x.posterUrl, 180, 240),
                      _imageSlot(
                        ImageKind.background,
                        x.backgroundUrl,
                        320,
                        180,
                      ),
                    ],
                  ),
                ]),
                _card('회비', [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(136),
                      columnWidths: const {0: FixedColumnWidth(80)},
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            _th('구분'),
                            for (final label in _feeCols.values) _th(label),
                          ],
                        ),
                        for (final ag in AgeGroup.values)
                          TableRow(
                            children: [
                              Text(
                                ag.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              for (final col in _feeCols.keys)
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: TextField(
                                    controller: fee['$col:${ag.name}'],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    decoration: InputDecoration(
                                      suffixText: col == 'minAge' ? '세~' : '원',
                                      hintText: col == 'full'
                                          ? '1박×${x.nights}'
                                          : '0',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '나이는 연 나이(집회 연도 − 출생연도)입니다. 전체 참석을 비워 두면 1박당 × ${x.nights}박으로 계산하고, '
                    '부분 참석 금액은 전체 참석 금액을 넘지 않습니다.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: perReg,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '가족(신청 1건)당 금액',
                        suffixText: '원',
                      ),
                    ),
                  ),
                ]),
                _card('할인', [
                  const Text(
                    '전체 참석 할인',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    '집회 기간 전체를 참석하는 사람의 금액에만 적용합니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 220,
                      child: TextField(
                        controller: fullPct,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '할인율',
                          suffixText: '%',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '사전등록 할인',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    '신청한 날이 집회 시작 며칠 전인지로 정합니다. 구간이 겹치면 큰 쪽 하나만 적용하고, '
                    '전체 참석 할인 뒤에 합계에서 한 번 더 뺍니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  for (final (i, e) in early.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('집회'),
                          _daysField(e.fromDays, '일 전부터'),
                          _daysField(e.toDays, '일 전까지'),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: e.pct,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '할인율',
                                suffixText: '%',
                              ),
                            ),
                          ),
                          Text(
                            _earlyDates(x.start, e),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          IconButton(
                            tooltip: '이 사전등록 할인 삭제',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => early.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('사전등록 할인 추가'),
                      onPressed: () =>
                          setState(() => early.add(_Early(30, 1, 10))),
                    ),
                  ),
                ]),
                _card('입금 계좌', [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: bank,
                          decoration: const InputDecoration(labelText: '은행'),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: account,
                          decoration: const InputDecoration(labelText: '계좌번호'),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: holder,
                          decoration: const InputDecoration(labelText: '예금주'),
                        ),
                      ),
                    ],
                  ),
                ]),
                _card('신청 받기', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('신청 받기'),
                    subtitle: Text(
                      x.open
                          ? '신청 웹에서 신청할 수 있습니다.'
                          : '신청 웹에 "지금은 신청을 받지 않습니다"가 보입니다.',
                    ),
                    value: x.open,
                    onChanged: (v) => setState(() => x.open = v),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.event_busy_outlined, size: 18),
                        label: Text(
                          x.deadline == null
                              ? '마감일 없음'
                              : '마감일 ${x.deadline!.year}-${mdw(x.deadline!)} 까지',
                        ),
                        onPressed: () async {
                          final d = await pickDate(
                            context,
                            x.deadline ?? dateOnly(x.start),
                          );
                          if (d != null) setState(() => x.deadline = d);
                        },
                      ),
                      if (x.deadline != null)
                        TextButton(
                          onPressed: () => setState(() => x.deadline = null),
                          child: const Text('마감일 지우기'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    applyLink(cur.id),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '신청서 추가 항목',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    '참석자 탭의 사용자 정의 항목이 신청서에 그대로 나옵니다. [저장]해야 반영됩니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in store.event.customFields)
                        Chip(label: Text(f)),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('항목 추가'),
                        onPressed: () async {
                          await addCustomFieldDialog(context);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ]),
                _card('집회 삭제', [
                  const Text(
                    '서버의 집회 설정과 신청 내역이 모두 지워집니다. 이 PC의 방배정 파일은 남습니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('집회 삭제'),
                      onPressed: () => _delete(cur),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _th(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );

  Widget _daysField(TextEditingController c, String suffix) => SizedBox(
    width: 130,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      decoration: InputDecoration(suffixText: suffix),
      onChanged: (_) => setState(() {}), // 옆의 실제 날짜 갱신
    ),
  );

  /// "09-09(수) ~ 10-08(목) 신청분". 숫자가 아니면 빈칸.
  String _earlyDates(DateTime start, _Early e) {
    final a = int.tryParse(e.fromDays.text.trim());
    final b = int.tryParse(e.toDays.text.trim());
    if (a == null || b == null) return '';
    final (from, to) = a >= b ? (a, b) : (b, a);
    return '${mdw(daysBefore(start, from))} ~ ${mdw(daysBefore(start, to))} 신청분';
  }

  Widget _dateButton(
    String label,
    DateTime d,
    void Function(DateTime) onPick,
  ) => OutlinedButton.icon(
    icon: const Icon(Icons.event, size: 18),
    label: Text('$label ${d.year}-${mdw(d)}'),
    onPressed: () async {
      final p = await pickDate(context, d);
      if (p != null) setState(() => onPick(p));
    },
  );

  Widget _imageSlot(ImageKind kind, String? url, double w, double h) =>
      SizedBox(
        width: w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind == ImageKind.poster ? '포스터 (세로)' : '배경 (가로)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: AppColors.border),
              ),
              child: uploading == kind
                  ? const Center(child: CircularProgressIndicator())
                  : url == null
                  ? const Icon(
                      Icons.image_outlined,
                      size: 32,
                      color: AppColors.textMuted,
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          '불러오지 못함',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: uploading != null ? null : () => _pickImage(kind),
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: Text(url == null ? '이미지 선택' : '바꾸기'),
                ),
                if (url != null)
                  TextButton(
                    onPressed: uploading != null
                        ? null
                        : () => _clearImage(kind),
                    child: const Text('지우기'),
                  ),
              ],
            ),
            Text(
              '가로 ${kind.maxWidth}px · ${kind.maxBytes ~/ 1024}KB 이하로 줄여서 올립니다',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );
}

String _size(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB'
    : '${(bytes / 1024).round()}KB';
