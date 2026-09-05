import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import 'rooms.dart' show genderLabel;

/// 배정 화면에서 미리 선택해둘 참석자 (현황 화면에서 넘어올 때 사용).
final pendingSelection = <String>{};

class AssignScreen extends StatefulWidget {
  const AssignScreen({super.key});

  @override
  State<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends State<AssignScreen> {
  final name = TextEditingController();
  final cell = TextEditingController();
  final zone = TextEditingController();
  final ageMin = TextEditingController();
  final ageMax = TextEditingController();
  String? gender;
  bool unassignedOnly = false;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    if (pendingSelection.isNotEmpty) {
      selected.addAll(pendingSelection);
      pendingSelection.clear();
      unassignedOnly = true;
    }
  }

  @override
  void dispose() {
    for (final c in [name, cell, zone, ageMin, ageMax]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _match(Attendee a) {
    bool has(TextEditingController c, String? field) {
      final q = c.text.trim().toLowerCase();
      return q.isEmpty || (field ?? '').toLowerCase().contains(q);
    }

    if (!has(name, a.name)) return false;
    if (!has(cell, a.cell)) return false;
    if (!has(zone, a.zone)) return false;
    if (gender != null && a.gender != gender) return false;
    if (unassignedOnly && a.roomId != null) return false;
    final lo = int.tryParse(ageMin.text.trim());
    final hi = int.tryParse(ageMax.text.trim());
    if (lo != null && a.age < lo) return false;
    if (hi != null && a.age > hi) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = store.event.attendees.where(_match).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chosen = store.event.attendees
        .where((a) => selected.contains(a.id))
        .toList();

    return Row(
      children: [
        SizedBox(width: 460, child: _left(filtered, chosen)),
        const VerticalDivider(width: 1),
        Expanded(child: _right(chosen)),
      ],
    );
  }

  Widget _left(List<Attendee> filtered, List<Attendee> chosen) {
    final allSelected =
        filtered.isNotEmpty && filtered.every((a) => selected.contains(a.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _field(name, '이름')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(cell, '셀')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(zone, '존')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(width: 96, child: _field(ageMin, '나이 ≥')),
                  const SizedBox(width: 8),
                  SizedBox(width: 96, child: _field(ageMax, '나이 ≤')),
                  const SizedBox(width: 12),
                  ...[(null, '전체'), ('M', '남'), ('F', '여')].map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(g.$2),
                        selected: gender == g.$1,
                        onSelected: (_) => setState(() => gender = g.$1),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Checkbox(
                    value: unassignedOnly,
                    onChanged: (v) => setState(() => unassignedOnly = v!),
                  ),
                  const Text('미배정만'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        selected.removeAll(filtered.map((a) => a.id));
                      } else {
                        selected.addAll(filtered.map((a) => a.id));
                      }
                    }),
                    child: Text(allSelected ? '전체 해제' : '결과 전체 선택'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '검색 ${filtered.length}명 · 선택 ${chosen.length}명',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final a = filtered[i];
              final room = store.roomById(a.roomId);
              return CheckboxListTile(
                dense: true,
                value: selected.contains(a.id),
                onChanged: (v) => setState(
                  () => v! ? selected.add(a.id) : selected.remove(a.id),
                ),
                title: Text(
                  '${a.name}  ${genderLabel(a.gender)} ${a.age}세'
                  '${room == null ? '' : '  → ${room.roomNo}'}',
                ),
                subtitle: Text(
                  [
                    if ((a.zone ?? '').isNotEmpty) '존:${a.zone}',
                    if ((a.cell ?? '').isNotEmpty) '셀:${a.cell}',
                    '${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}',
                  ].join('  '),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) => setState(() {}),
  );

  Widget _right(List<Attendee> chosen) {
    final rooms = [...store.event.rooms]
      ..sort(
        (a, b) => (a.roomNumber ?? 999999).compareTo(b.roomNumber ?? 999999),
      );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '선택 ${chosen.length}명',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: chosen.isEmpty ? null : () => _setStay(chosen),
                icon: const Icon(Icons.date_range),
                label: const Text('체크인/아웃 지정'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: chosen.isEmpty
                    ? null
                    : () {
                        store.assignAll(chosen, null);
                        setState(() {});
                      },
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('배정 해제'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              chosen.isEmpty
                  ? '왼쪽에서 인원을 선택한 뒤 방을 클릭하세요.'
                  : '방을 클릭하면 선택한 인원이 일괄 배정됩니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: rooms.isEmpty
              ? const Center(child: Text('방이 없습니다.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in rooms)
                        RoomTile(
                          room: r,
                          onTap: chosen.isEmpty
                              ? null
                              : () => _assign(chosen, r),
                          onLongPress: () => _showOccupants(r),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _assign(List<Attendee> chosen, Room room) async {
    // 날짜 겹침까지 반영한 실제 결과를 보려면 잠깐 배정해보고 되돌린다.
    final before = {for (final a in chosen) a.id: a.roomId};
    for (final a in chosen) {
      a.roomId = room.id;
    }
    final after = store.peakOccupancy(room);
    for (final a in chosen) {
      a.roomId = before[a.id];
    }
    if (after > room.capacity) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('정원 초과'),
          content: Text(
            '${room.roomNo}호는 정원 ${room.capacity}명인데 최대 $after명이 됩니다.\n'
            '그래도 배정할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('배정'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    store.assignAll(chosen, room.id);
    if (mounted) setState(() {});
  }

  Future<void> _setStay(List<Attendee> chosen) async {
    var ci = chosen.first.checkIn;
    var co = chosen.first.checkOut;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${chosen.length}명 체크인/체크아웃'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('체크인'),
                trailing: Text(fmtDate(ci)),
                onTap: () async {
                  final d = await pickDate(context, ci);
                  if (d != null) setLocal(() => ci = d);
                },
              ),
              ListTile(
                title: const Text('체크아웃'),
                trailing: Text(fmtDate(co)),
                onTap: () async {
                  final d = await pickDate(context, co);
                  if (d != null) setLocal(() => co = d);
                },
              ),
              TextButton(
                onPressed: () => setLocal(() {
                  ci = store.event.startDate;
                  co = store.event.endDate;
                }),
                child: const Text('전체 일정으로 되돌리기'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!co.isAfter(ci)) co = ci.add(const Duration(days: 1));
    store.setStay(chosen, ci, co);
    if (mounted) setState(() {});
  }

  void _showOccupants(Room room) => showRoomOccupants(context, room);
}

/// 방 카드. 배정/수용 배지 + 성별 표시.
class RoomTile extends StatelessWidget {
  const RoomTile({super.key, required this.room, this.onTap, this.onLongPress});
  final Room room;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final used = store.peakOccupancy(room);
    final over = used > room.capacity;
    final full = used == room.capacity;
    final color = used == 0
        ? Colors.grey.shade200
        : over
        ? Colors.red.shade200
        : full
        ? Colors.blue.shade200
        : Colors.green.shade200;
    return SizedBox(
      width: 130,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      room.roomNo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (room.gender != null)
                      Text(
                        genderLabel(room.gender!),
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$used / ${room.capacity}${over ? '  초과' : ''}',
                  style: TextStyle(
                    fontWeight: over ? FontWeight.bold : FontWeight.normal,
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

Future<void> showRoomOccupants(BuildContext context, Room room) {
  final list = store.occupantsOf(room)
    ..sort((a, b) => a.name.compareTo(b.name));
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        '${room.roomNo}호  ${store.peakOccupancy(room)}/${room.capacity}'
        '  (배정 ${list.length}명)',
      ),
      content: SizedBox(
        width: 380,
        child: list.isEmpty
            ? const Text('배정된 인원이 없습니다.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in list)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${a.name}  ${genderLabel(a.gender)} ${a.age}세',
                      ),
                      subtitle: Text(
                        '${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}  ${a.zone ?? ''} ${a.cell ?? ''}',
                      ),
                      trailing: IconButton(
                        tooltip: '배정 해제',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          store.assignAll([a], null);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}
