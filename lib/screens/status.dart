import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import 'assign.dart' show RoomTile, showRoomOccupants, pendingSelection;

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final e = store.event;
    final assigned = e.attendees.where((a) => a.roomId != null).length;
    final unassigned = store.unassigned;
    final free = store.event.rooms
        .map(store.freeSeats)
        .fold(0, (s, x) => s + (x > 0 ? x : 0));
    final roomsByFloor = _byFloor(e.rooms);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Stat('총원', '${e.attendees.length}명'),
            _Stat('배정완료', '$assigned명', color: Colors.blue),
            _Stat(
              '미배정',
              '${unassigned.length}명',
              color: unassigned.isEmpty ? Colors.green : Colors.orange,
            ),
            _Stat('총 수용', '${store.totalCapacity}명'),
            _Stat('잔여 좌석', '$free석', color: Colors.green),
          ],
        ),
        const SizedBox(height: 24),
        Text('전체 구조', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          '회색=빈방 · 초록=여유 · 파랑=만실 · 빨강=초과 (클릭하면 인원 목록)',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (e.rooms.isEmpty)
          const Text('방이 없습니다.')
        else
          for (final entry in roomsByFloor.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                entry.key == null ? '기타' : '${entry.key}층',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in entry.value)
                  RoomTile(room: r, onTap: () => showRoomOccupants(context, r)),
              ],
            ),
          ],
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Panel(
                title: '미배정 인원 (${unassigned.length}명)',
                action: unassigned.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () {
                          pendingSelection
                            ..clear()
                            ..addAll(unassigned.map((a) => a.id));
                          tabIndex.value = 2;
                        },
                        child: const Text('전체 선택해서 배정하기'),
                      ),
                children: [
                  for (final a in unassigned.take(200))
                    ListTile(
                      dense: true,
                      title: Text(
                        '${a.name}  ${a.gender == 'M' ? '남' : '여'} ${a.age}세',
                      ),
                      subtitle: Text(
                        [
                          if ((a.zone ?? '').isNotEmpty) '존:${a.zone}',
                          if ((a.cell ?? '').isNotEmpty) '셀:${a.cell}',
                        ].join('  '),
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
              child: _Panel(
                title: '여유 있는 방',
                children: [
                  for (final r
                      in e.rooms.where((r) => store.freeSeats(r) > 0).toList()
                        ..sort(
                          (a, b) =>
                              store.freeSeats(b).compareTo(store.freeSeats(a)),
                        ))
                    ListTile(
                      dense: true,
                      title: Text('${r.roomNo}호'),
                      subtitle: Text(
                        '${store.peakOccupancy(r)}/${r.capacity}'
                        '${r.gender == null ? '' : '  ${r.gender == 'M' ? '남' : '여'}'}',
                      ),
                      trailing: Text(
                        '+${store.freeSeats(r)}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => showRoomOccupants(context, r),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Map<int?, List<Room>> _byFloor(List<Room> rooms) {
  final sorted = [
    ...rooms,
  ]..sort((a, b) => (a.roomNumber ?? 999999).compareTo(b.roomNumber ?? 999999));
  final map = <int?, List<Room>>{};
  for (final r in sorted) {
    map.putIfAbsent(r.floor, () => []).add(r);
  }
  final keys = map.keys.toList()
    ..sort((a, b) => (a ?? 9999).compareTo(b ?? 9999));
  return {for (final k in keys) k: map[k]!};
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              ?action,
            ],
          ),
        ),
        const Divider(height: 1),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('없음', style: TextStyle(color: Colors.grey)),
          )
        else
          ...children,
      ],
    ),
  );
}
