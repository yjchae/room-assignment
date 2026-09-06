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
                  subtitle: Text(
                    [
                      if ((x.attendee.zone ?? '').isNotEmpty)
                        '존:${x.attendee.zone}',
                      if ((x.attendee.cell ?? '').isNotEmpty)
                        '셀:${x.attendee.cell}',
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
