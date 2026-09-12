import 'package:flutter/material.dart';

import '../auto_assign.dart';
import '../main.dart';
import '../theme.dart';

class AutoAssignScreen extends StatefulWidget {
  const AutoAssignScreen({super.key});

  @override
  State<AutoAssignScreen> createState() => _AutoAssignScreenState();
}

class _AutoAssignScreenState extends State<AutoAssignScreen> {
  bool useAge = true;
  final age = TextEditingController(text: '65');
  final keyword = TextEditingController();
  String zoneMode = 'floor'; // 'floor' | 'roomNo' | 'none'
  final floorMin = TextEditingController(text: '1');
  final floorMax = TextEditingController(text: '2');
  final noMin = TextEditingController();
  final noMax = TextEditingController();
  bool separateGender = true;

  /// 같이 배정할 기준. 목록 순서가 곧 우선순위(위가 1순위), 체크된 것만 쓴다.
  /// 운영자가 만든 항목(교회 등)도 여기에 자동으로 들어온다.
  List<GroupField> groupOrder = [];
  Set<GroupField> groupOn = {GroupField.zone, GroupField.cell};

  /// 이 집회에서 고를 수 있는 기준 = 기본 항목 + 사용자 정의 항목.
  /// 운영자가 정한 순서를 지키되, 새 항목은 뒤에 붙이고 지워진 항목은 뺀다.
  List<GroupField> get _fields {
    final all = GroupField.forEvent(store.event);
    final kept = groupOrder.where(all.contains).toList();
    return [...kept, ...all.where((f) => !kept.contains(f))];
  }

  List<GroupField> get _groupBy => _fields.where(groupOn.contains).toList();

  AutoAssignResult? result;

  @override
  void dispose() {
    for (final c in [age, keyword, floorMin, floorMax, noMin, noMax]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 체크는 켜져 있는데 숫자가 비었거나 오타면 규칙이 조용히 꺼진다 → 실행을 막는다.
  bool get _ageValid => !useAge || int.tryParse(age.text.trim()) != null;

  AutoRule _rule() => AutoRule(
    priorityAge: useAge ? int.tryParse(age.text.trim()) : null,
    priorityKeyword: keyword.text.trim().isEmpty ? null : keyword.text.trim(),
    floorMin: zoneMode == 'floor' ? int.tryParse(floorMin.text.trim()) : null,
    floorMax: zoneMode == 'floor' ? int.tryParse(floorMax.text.trim()) : null,
    roomNoMin: zoneMode == 'roomNo' ? int.tryParse(noMin.text.trim()) : null,
    roomNoMax: zoneMode == 'roomNo' ? int.tryParse(noMax.text.trim()) : null,
    separateGender: separateGender,
    groupBy: _groupBy,
  );

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Row(
      children: [
        SizedBox(width: 380, child: _settings()),
        const VerticalDivider(width: 1),
        Expanded(
          child: r == null
              ? const Center(child: Text('규칙을 정하고 [미리보기]를 누르세요.'))
              : _preview(r),
        ),
      ],
    );
  }

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('우대 대상', style: Theme.of(context).textTheme.titleMedium),
      Row(
        children: [
          Checkbox(
            value: useAge,
            onChanged: (v) => setState(() => useAge = v!),
          ),
          const Text('나이 ≥'),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: age,
              enabled: useAge,
              decoration: InputDecoration(
                isDense: true,
                errorText: _ageValid ? null : '숫자',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      TextField(
        controller: keyword,
        decoration: const InputDecoration(
          labelText: '기타사항 키워드',
          helperText: '예: 강사 — 비워두면 사용 안 함',
        ),
      ),
      const SizedBox(height: 20),
      _groupSection(),
      const SizedBox(height: 20),
      Text('우대 배정 구역', style: Theme.of(context).textTheme.titleMedium),
      RadioGroup<String>(
        groupValue: zoneMode,
        onChanged: (v) => setState(() => zoneMode = v!),
        child: Column(
          children: [
            RadioListTile(
              value: 'floor',
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Text('층 '),
                  _num(floorMin, zoneMode == 'floor'),
                  const Text(' ~ '),
                  _num(floorMax, zoneMode == 'floor'),
                ],
              ),
            ),
            RadioListTile(
              value: 'roomNo',
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Text('호수 '),
                  _num(noMin, zoneMode == 'roomNo'),
                  const Text(' ~ '),
                  _num(noMax, zoneMode == 'roomNo'),
                ],
              ),
            ),
            const RadioListTile(
              value: 'none',
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('제한 없음'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: separateGender,
        onChanged: (v) => setState(() => separateGender = v),
        title: const Text('성별 분리'),
        subtitle: const Text('방 성별이 없으면 첫 배정자 성별로 고정'),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: !_ageValid
            ? null
            : () => setState(() => result = autoAssign(store.event, _rule())),
        icon: const Icon(Icons.auto_awesome),
        label: Text('미리보기 (미배정 ${store.unassigned.length}명)'),
      ),
    ],
  );

  /// 같이 배정할 기준 고르기 + 순서 바꾸기.
  /// 순서가 우선순위다 — 자리가 모자라면 아래쪽(덜 중요한) 기준부터 포기한다.
  Widget _groupSection() {
    final on = _groupBy;
    final fields = _fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('같이 배정할 기준'),
        const SizedBox(height: 4),
        Text(
          '체크한 항목의 값이 같은 사람을 한 방에 모은다.\n'
          '위에 있을수록 우선순위가 높고, 자리가 모자라면 아래 기준부터 포기한다.',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // onReorderItem 은 항목을 뺀 뒤 기준으로 to 를 이미 보정해서 준다.
            onReorderItem: (from, to) => setState(() {
              final list = _fields;
              list.insert(to, list.removeAt(from));
              groupOrder = list;
            }),
            children: [
              for (var i = 0; i < fields.length; i++)
                _groupTile(i, fields[i], on),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          on.isEmpty
              ? '기준이 없으면 그룹으로 묶지 않고 빈자리부터 채운다.'
              : '현재 순서: ${on.map((f) => f.label).join(' → ')}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on.isEmpty ? AppColors.textMuted : AppColors.brand,
          ),
        ),
      ],
    );
  }

  Widget _groupTile(int index, GroupField f, List<GroupField> on) {
    final rank = on.indexOf(f);
    return ListTile(
      key: ValueKey(f),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 4, right: 8),
      leading: Checkbox(
        value: groupOn.contains(f),
        onChanged: (v) =>
            setState(() => v! ? groupOn.add(f) : groupOn.remove(f)),
      ),
      title: Text(
        f.label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: rank < 0 ? AppColors.textMuted : AppColors.text,
        ),
      ),
      subtitle: rank < 0
          ? null
          : Text(
              '${rank + 1}순위',
              style: const TextStyle(fontSize: 11, color: AppColors.brand),
            ),
      trailing: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle, color: AppColors.textMuted),
      ),
    );
  }

  Widget _num(TextEditingController c, bool enabled) => SizedBox(
    width: 60,
    child: TextField(
      controller: c,
      enabled: enabled,
      decoration: const InputDecoration(isDense: true),
      keyboardType: TextInputType.number,
    ),
  );

  Widget _preview(AutoAssignResult r) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '배정 예정 ${r.assignments.length}명'
                '${r.unplaced.isEmpty ? '' : ' · 자리 없음 ${r.unplaced.length}명'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => result = null),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: r.assignments.isEmpty
                    ? null
                    : () {
                        applyAssignments(r.assignments);
                        store.commit();
                        final n = r.assignments.length;
                        setState(() => result = null);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$n명 배정 완료')));
                      },
                child: const Text('적용'),
              ),
            ],
          ),
        ),
        if (r.priorityOutsideZone.isNotEmpty)
          Container(
            width: double.infinity,
            color: AppColors.warn.withValues(alpha: 0.15),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '우대 대상 ${r.priorityOutsideZone.length}명'
              '(${r.priorityOutsideZone.take(3).map((a) => a.name).join(', ')}'
              '${r.priorityOutsideZone.length > 3 ? ' 외' : ''})은 '
              '지정한 구역에 빈자리가 없어 다른 층에 배정됩니다.',
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: r.assignments.length + r.unplaced.length,
            itemBuilder: (context, i) {
              if (i < r.assignments.length) {
                final x = r.assignments[i];
                return ListTile(
                  dense: true,
                  leading: Chip(
                    label: Text(x.stage),
                    visualDensity: VisualDensity.compact,
                  ),
                  title: Text(
                    '${x.attendee.name}  '
                    '${genderLabel(x.attendee.gender)} ${x.attendee.age}세',
                  ),
                  // 고른 기준 그대로 보여준다 (기준이 바뀌면 여기도 따라간다).
                  subtitle: Text(
                    [
                      for (final f in _groupBy)
                        if ((f.of(x.attendee) ?? '').trim().isNotEmpty)
                          f == GroupField.family
                              ? f.label
                              : '${f.label}:${f.of(x.attendee)}',
                    ].join('  '),
                  ),
                  trailing: Text(
                    '→ ${x.room.roomNo}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }
              final a = r.unplaced[i - r.assignments.length];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text('${a.name}  ${genderLabel(a.gender)} ${a.age}세'),
                trailing: const Text(
                  '자리 없음',
                  style: TextStyle(color: Colors.red),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
