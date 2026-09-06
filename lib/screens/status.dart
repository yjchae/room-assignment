import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets/room_board.dart';
import 'assign.dart' show showRoomOccupants, pendingSelection;

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final e = store.event;
    final assigned = e.attendees.where((a) => a.roomId != null).length;
    final unassigned = store.unassigned;
    final free = e.rooms
        .map(store.freeSeats)
        .fold(0, (s, x) => s + (x > 0 ? x : 0));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatCard('총원', '${e.attendees.length}', unit: '명'),
            StatCard('배정완료', '$assigned', unit: '명', color: AppColors.info),
            StatCard(
              '미배정',
              '${unassigned.length}',
              unit: '명',
              color: unassigned.isEmpty ? AppColors.ok : AppColors.warn,
            ),
            StatCard('총 수용', '${store.totalCapacity}', unit: '명'),
            StatCard('잔여 좌석', '$free', unit: '석', color: AppColors.ok),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: SectionTitle('전체 구조', subtitle: '타일을 클릭하면 그 방 인원이 나옵니다'),
            ),
            const SizedBox(width: 16),
            const RoomLegend(),
          ],
        ),
        const SizedBox(height: 10),
        RoomBoard(rooms: e.rooms, onTap: (r) => showRoomOccupants(context, r)),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Panel(
                title: '미배정 인원',
                count: unassigned.length,
                action: unassigned.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () {
                          pendingSelection
                            ..clear()
                            ..addAll(unassigned.map((a) => a.id));
                          tabIndex.value = 2;
                        },
                        child: const Text('전체 선택해서 배정'),
                      ),
                children: [
                  for (final a in unassigned.take(200))
                    ListTile(
                      dense: true,
                      title: Row(
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 6),
                          GenderBadge(a.gender),
                          const SizedBox(width: 6),
                          Text(
                            '${a.age}세',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          if ((a.zone ?? '').isNotEmpty) '존 ${a.zone}',
                          if ((a.cell ?? '').isNotEmpty) '셀 ${a.cell}',
                        ].join('  ·  '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () {
                        pendingSelection
                          ..clear()
                          ..add(a.id);
                        tabIndex.value = 2;
                      },
                    ),
                  if (unassigned.length > 200)
                    const ListTile(dense: true, title: Text('... 이하 생략')),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: () {
                final spare =
                    e.rooms.where((r) => store.freeSeats(r) > 0).toList()..sort(
                      (a, b) =>
                          store.freeSeats(b).compareTo(store.freeSeats(a)),
                    );
                return _Panel(
                  title: '여유 있는 방',
                  count: spare.length,
                  children: [
                    for (final r in spare)
                      ListTile(
                        dense: true,
                        title: Row(
                          children: [
                            Text(
                              '${r.roomNo}호',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (r.gender != null) GenderBadge(r.gender!),
                          ],
                        ),
                        subtitle: Text(
                          '${store.peakOccupancy(r)}/${r.capacity}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          '+${store.freeSeats(r)}',
                          style: const TextStyle(
                            color: AppColors.ok,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onTap: () => showRoomOccupants(context, r),
                      ),
                  ],
                );
              }(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.children,
    this.count,
    this.action,
  });
  final String title;
  final int? count;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
              ],
              const Spacer(),
              ?action,
            ],
          ),
        ),
        const Divider(height: 1),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('없음', style: TextStyle(color: AppColors.textMuted)),
          )
        else
          ...children,
      ],
    ),
  );
}
