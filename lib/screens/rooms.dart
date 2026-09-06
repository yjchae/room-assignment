import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/room_board.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = [...store.event.rooms]..sort(byRoomNo);
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _roomDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('방 추가'),
      ),
      body: rooms.isEmpty
          ? const Center(
              child: Text(
                '방이 없습니다. [방 추가]로 "301-310" 처럼 범위를 넣으면 한 번에 만들어집니다.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    StatCard('방', '${rooms.length}', unit: '개'),
                    StatCard('총 수용', '${store.totalCapacity}', unit: '명'),
                    StatCard(
                      '잔여 좌석',
                      '${rooms.map(store.freeSeats).fold(0, (s, x) => s + (x > 0 ? x : 0))}',
                      unit: '석',
                      color: AppColors.ok,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                for (final entry in _byFloor(rooms).entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: SectionTitle(
                      entry.key == null ? '기타' : '${entry.key}층',
                      subtitle:
                          '${entry.value.length}실 · 수용 '
                          '${entry.value.fold(0, (s, r) => s + r.capacity)}명',
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [for (final r in entry.value) _RoomCard(room: r)],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}

Map<int?, List<Room>> _byFloor(List<Room> rooms) {
  final map = <int?, List<Room>>{};
  for (final r in rooms) {
    map.putIfAbsent(r.floor, () => []).add(r);
  }
  final keys = map.keys.toList()
    ..sort((a, b) => (b ?? -9999).compareTo(a ?? -9999));
  return {for (final k in keys) k: map[k]!};
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final used = store.peakOccupancy(room);
    final st = statusOf(used: used, capacity: room.capacity);
    return SizedBox(
      width: 196,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: () => _roomDialog(context, room),
          borderRadius: BorderRadius.circular(Radii.card),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: st.swatch,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      room.roomNo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const Spacer(),
                    if (room.gender != null) GenderBadge(room.gender!),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$used',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      ' / ${room.capacity}명',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      st.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: st == RoomStatus.empty
                            ? AppColors.textMuted
                            : st.swatch,
                      ),
                    ),
                  ],
                ),
                if ((room.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      room.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [room] 이 null 이면 추가(범위 지원), 있으면 수정.
Future<void> _roomDialog(BuildContext context, [Room? room]) async {
  final noCtl = TextEditingController(text: room?.roomNo ?? '');
  final capCtl = TextEditingController(text: '${room?.capacity ?? 4}');
  final noteCtl = TextEditingController(text: room?.note ?? '');
  String? gender = room?.gender;
  final messenger = ScaffoldMessenger.of(context);

  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(room == null ? '방 추가' : '방 ${room.roomNo} 수정'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: noCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '호수',
                  helperText: room == null ? '범위 가능: 301-310, 401' : null,
                ),
              ),
              TextField(
                controller: capCtl,
                decoration: const InputDecoration(labelText: '수용 인원'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('성별  '),
                  ...[(null, '무관'), ('M', '남'), ('F', '여')].map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(g.$2),
                        selected: gender == g.$1,
                        onSelected: (_) => setLocal(() => gender = g.$1),
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: noteCtl,
                decoration: const InputDecoration(labelText: '기타'),
              ),
            ],
          ),
        ),
        actions: [
          if (room != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text(
                '삭제',
                style: TextStyle(color: AppColors.danger),
              ),
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
    ),
  );

  if (action == null || action == 'cancel') return;

  if (action == 'delete' && room != null) {
    final n = store.occupantsOf(room).length;
    if (n > 0) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('배정된 인원이 있습니다'),
          content: Text('$n명이 이 방에 배정되어 있습니다. 삭제하면 미배정으로 되돌아갑니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final freed = store.deleteRoom(room);
    messenger.showSnackBar(
      SnackBar(content: Text('삭제됨. 미배정으로 되돌린 인원 $freed명')),
    );
    return;
  }

  final cap = int.tryParse(capCtl.text.trim()) ?? 0;
  if (cap <= 0) {
    messenger.showSnackBar(const SnackBar(content: Text('수용 인원은 1 이상이어야 합니다')));
    return;
  }
  final note = noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim();

  if (room != null) {
    final no = noCtl.text.trim();
    if (no.isEmpty) return;
    room
      ..roomNo = no
      ..capacity = cap
      ..gender = gender
      ..note = note;
    store.commit();
    return;
  }

  final (made, skipped) = store.addRoomRange(
    noCtl.text,
    capacity: cap,
    gender: gender,
    note: note,
  );
  if (made == 0 && skipped == 0) {
    messenger.showSnackBar(
      const SnackBar(content: Text('호수를 인식하지 못했습니다. 예: 301 또는 301-310')),
    );
  } else {
    messenger.showSnackBar(
      SnackBar(
        content: Text('$made개 생성${skipped > 0 ? ' · 중복 $skipped개 건너뜀' : ''}'),
      ),
    );
  }
}
