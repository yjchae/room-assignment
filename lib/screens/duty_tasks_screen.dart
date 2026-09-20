import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/duty_tasks.dart';

/// 담당구역 할일. 스탭이 스탭 페이지(`?g=…&staff=1`)에서 적은 표를 모두 모아 보여주고,
/// 운영자도 같은 표로 고칠 수 있다. 구역·인원은 [담당구역] 화면에서 만든다.
class DutyTasksScreen extends StatelessWidget {
  const DutyTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final duties = store.event.duties;
    final total = duties.fold(0, (s, d) => s + d.items.length);
    final done = duties.fold(0, (s, d) => s + d.doneCount);
    final id = current.value?.id;
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
                '담당구역 할일',
                subtitle:
                    '구역 ${duties.length}개 · 할 일 $total개 · 완료 $done개'
                    '${total == 0 ? ' — 스탭이 스탭 페이지에서 적거나 여기서 바로 적습니다' : ''}',
              ),
              OutlinedButton.icon(
                onPressed: id == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: staffLink(id)));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('스탭 페이지 링크를 복사했습니다. 담당구역을 맡은 사람에게 보내세요.'),
                          ),
                        );
                      },
                icon: const Icon(Icons.link, size: 18),
                label: const Text('스탭 페이지 링크 복사'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (duties.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: EmptyNotice(
              icon: Icons.fact_check_outlined,
              text: '담당구역이 없습니다. [담당구역]에서 구역을 만들고 사람을 배정하면\n여기에 그 구역의 할 일이 모입니다.',
              action: FilledButton(
                onPressed: () => tabIndex.value = dutiesTab,
                child: const Text('담당구역으로'),
              ),
            ),
          )
        else
          for (final d in duties)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                        child: SectionTitle(
                          d.name,
                          subtitle: [
                            '인원 ${d.personIds.length}명',
                            if (store.membersOf(d).isNotEmpty)
                              store.membersOf(d).map((a) => a.name).join(', '),
                          ].join(' · '),
                        ),
                      ),
                      Text(
                        '${d.doneCount}/${d.items.length}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabular,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if ((d.tasks ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        d.tasks!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DutyTaskTable(
                    key: ValueKey(d.id),
                    items: d.items,
                    newId: store.newId,
                    // ponytail: 한 칸 고칠 때마다 저장한다. Store 가 저장 중이면 끝난 뒤 한 번만
                    // 더 올리므로 왕복이 쌓이지 않는다. 더 아끼려면 여기서 몇 초 묶으면 된다.
                    onChanged: store.commit,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
