import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

/// 담당구역. 스탭이 맡을 일(주방·차량·등록대…)을 만들고 참석자를 배정한다.
/// 배정은 사람 단위라 기간을 나눈 조각([Attendee.splitOf])은 목록에 따로 나오지 않는다.
class DutiesScreen extends StatelessWidget {
  const DutiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final duties = store.event.duties;
    final assigned = {for (final d in duties) ...d.personIds};
    final idleStaff = _people
        .where((a) => a.staff && !assigned.contains(a.personId))
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SectionTitle(
                '담당구역',
                subtitle:
                    '구역 ${duties.length}개 · 배정 ${assigned.length}명'
                    '${idleStaff > 0 ? ' · 아직 구역이 없는 스탭 $idleStaff명' : ''}',
              ),
              FilledButton.icon(
                onPressed: () => _dutyDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('구역 추가'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (duties.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: EmptyNotice(
              icon: Icons.checklist_outlined,
              text:
                  '담당구역이 없습니다. [구역 추가]로 주방·차량·등록대처럼 맡을 일을 만들고\n'
                  '참석자를 배정하세요.',
              action: FilledButton(
                onPressed: () => _dutyDialog(context),
                child: const Text('구역 추가'),
              ),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final d in duties) _DutyCard(d)],
          ),
      ],
    );
  }
}

/// 배정 후보 = 기간을 나누지 않은 참석자 행 (같은 사람이 두 줄로 나오지 않게).
List<Attendee> get _people => [
  for (final a in store.event.attendees)
    if (a.splitOf == null) a,
];

class _DutyCard extends StatelessWidget {
  const _DutyCard(this.duty);
  final Duty duty;

  @override
  Widget build(BuildContext context) {
    final members = store.membersOf(duty);
    final cap = duty.capacity;
    final status = cap == null
        ? null
        : statusOf(used: members.length, capacity: cap);
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  duty.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status?.fill ?? AppColors.fill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cap == null ? '${members.length}명' : '${members.length}/$cap',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabular,
                    color: status?.ink ?? AppColors.textMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: '구역 수정',
                visualDensity: VisualDensity.compact,
                onPressed: () => _dutyDialog(context, duty),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (duty.tasks ?? '').trim().isEmpty ? '해야 할 일을 적지 않았습니다.' : duty.tasks!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: (duty.tasks ?? '').trim().isEmpty
                  ? AppColors.textFaint
                  : AppColors.textMuted,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in members)
                InputChip(
                  label: Text(a.name),
                  avatar: a.staff
                      ? const Icon(Icons.badge_outlined, size: 14)
                      : null,
                  onDeleted: () => store.setDutyMembers(
                    duty,
                    duty.personIds.where((p) => p != a.personId),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('인원 배정'),
                onPressed: () => _pickMembers(context, duty),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [duty] 가 null 이면 추가, 있으면 수정.
Future<void> _dutyDialog(BuildContext context, [Duty? duty]) async {
  final nameCtl = TextEditingController(text: duty?.name ?? '');
  final capCtl = TextEditingController(text: duty?.capacity?.toString() ?? '');
  final tasksCtl = TextEditingController(text: duty?.tasks ?? '');
  final messenger = ScaffoldMessenger.of(context);

  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(duty == null ? '담당구역 추가' : '${duty.name} 수정'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            const SizedBox(height: 4),
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '구역 이름',
                hintText: '예: 주방, 차량, 등록대',
              ),
            ),
            TextField(
              controller: capCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '필요 인원 (선택)',
                helperText: '비우면 인원 수만 보여줍니다.',
              ),
            ),
            TextField(
              controller: tasksCtl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '해야 할 일',
                hintText: '식사 준비 · 배식 · 뒷정리',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (duty != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'ok'),
          child: const Text('저장'),
        ),
      ],
    ),
  );
  if (action == null || action == 'cancel') return;

  if (action == 'delete' && duty != null) {
    final n = duty.personIds.length;
    if (!context.mounted) return;
    final ok =
        n == 0 ||
        await confirmDialog(
          context,
          title: '담당구역 삭제',
          body: '$n명이 이 구역에 배정되어 있습니다. 삭제하면 배정이 풀립니다.',
          action: '삭제',
          danger: true,
        );
    if (ok) store.deleteDuty(duty);
    return;
  }

  final name = nameCtl.text.trim();
  if (name.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('구역 이름을 입력하세요')));
    return;
  }
  final cap = int.tryParse(capCtl.text.trim());
  if (capCtl.text.trim().isNotEmpty && (cap == null || cap <= 0)) {
    messenger.showSnackBar(const SnackBar(content: Text('필요 인원은 1 이상이어야 합니다')));
    return;
  }
  final tasks = tasksCtl.text.trim().isEmpty ? null : tasksCtl.text.trim();
  if (duty == null) {
    store.addDuty(
      Duty(id: store.newId(), name: name, capacity: cap, tasks: tasks),
    );
  } else {
    duty
      ..name = name
      ..capacity = cap
      ..tasks = tasks;
    store.commit();
  }
}

/// 참석자 중에서 이 구역을 맡을 사람을 고른다. 겸임은 막지 않고 맡은 구역을 옆에 적어 준다.
Future<void> _pickMembers(BuildContext context, Duty duty) async {
  final picked = {...duty.personIds};
  var query = '';
  var staffOnly = false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        final list = store
            .search(query, _people)
            .where((a) => !staffOnly || a.staff)
            .toList();
        return AlertDialog(
          title: Text('${duty.name} 인원 배정'),
          content: SizedBox(
            width: 440,
            height: 460,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '이름 / 셀 / 존 검색',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('스탭만'),
                      selected: staffOnly,
                      onSelected: (v) => setLocal(() => staffOnly = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: list.isEmpty
                      ? EmptyNotice(
                          icon: Icons.person_search_outlined,
                          text: staffOnly
                              ? '스탭으로 신청한 참석자가 없습니다.\n집회 설정에서 스탭신청 칸을 켜거나, [스탭만]을 풀고 고르세요.'
                              : '참석자가 없습니다. [참석자] 탭에서 먼저 등록하세요.',
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final a = list[i];
                            final other = [
                              for (final d in store.dutiesOf(a))
                                if (d.id != duty.id) d.name,
                            ];
                            return CheckboxListTile(
                              dense: true,
                              value: picked.contains(a.personId),
                              onChanged: (v) => setLocal(() {
                                if (v == true) {
                                  picked.add(a.personId);
                                } else {
                                  picked.remove(a.personId);
                                }
                              }),
                              title: Text(
                                '${a.name}'
                                '${a.staff ? ' · 스탭' : ''}',
                              ),
                              subtitle: Text(
                                [
                                  genderLabel(a.gender),
                                  if (a.age > 0) '${a.age}세',
                                  if ((a.cell ?? '').isNotEmpty) '셀 ${a.cell}',
                                  if ((a.zone ?? '').isNotEmpty) '존 ${a.zone}',
                                  if (other.isNotEmpty) '담당 ${other.join(", ")}',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            Text(
              '${picked.length}명 선택',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('배정'),
            ),
          ],
        );
      },
    ),
  );
  if (ok == true) store.setDutyMembers(duty, picked);
}
