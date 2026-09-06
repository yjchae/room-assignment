import 'package:flutter/material.dart';

import '../auto_assign.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
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

  /// 다중 선택된 방. 단체를 여러 방에 나눠 넣을 때 쓴다.
  final selectedRooms = <String>{};
  final roomRange = TextEditingController();

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
    for (final c in [name, cell, zone, ageMin, ageMax, roomRange]) {
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
        // Row + Spacer 를 쓰면 창이 좁을 때 그대로 넘친다(RenderFlex overflow).
        // 버튼 수가 늘었으므로 접히는 Wrap 으로 둔다.
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '선택 ${chosen.length}명 · 방 ${selectedRooms.length}개',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.icon(
                onPressed: chosen.isEmpty || selectedRooms.isEmpty
                    ? null
                    : () => _assignToRooms(chosen),
                icon: const Icon(Icons.login),
                label: Text(
                  '${chosen.length}명 → ${selectedRooms.length}개 방 배정',
                ),
              ),
              OutlinedButton.icon(
                onPressed: chosen.isEmpty ? null : () => _setStay(chosen),
                icon: const Icon(Icons.date_range),
                label: const Text('체크인/아웃 지정'),
              ),
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
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: roomRange,
                      decoration: const InputDecoration(
                        labelText: '호수 범위로 방 선택',
                        hintText: '301-304, 401',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _selectRoomRange(rooms),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _selectRoomRange(rooms),
                    child: const Text('선택'),
                  ),
                  TextButton(
                    onPressed: selectedRooms.isEmpty
                        ? null
                        : () => setState(selectedRooms.clear),
                    child: const Text('방 선택 해제'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                chosen.isEmpty
                    ? '왼쪽에서 인원을 고르고, 방을 클릭해 여러 개 선택하세요.'
                    : '방을 클릭해 여러 개 고른 뒤 [배정]을 누르면 호수 순으로 채웁니다.'
                          ' (길게 누르면 인원 목록)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                          selected: selectedRooms.contains(r.id),
                          onTap: () => setState(
                            () => selectedRooms.contains(r.id)
                                ? selectedRooms.remove(r.id)
                                : selectedRooms.add(r.id),
                          ),
                          onLongPress: () => _showOccupants(r),
                        ),
                    ],
                  ),
                ),
        ),
        if (selectedRooms.isNotEmpty) _roomDetails(rooms),
      ],
    );
  }

  /// 선택한 방에 누가 들어있는지 보여주는 패널.
  /// 방을 클릭하면(=선택하면) 바로 여기에 인원이 뜬다.
  Widget _roomDetails(List<Room> rooms) {
    final picked = rooms.where((r) => selectedRooms.contains(r.id)).toList();
    return Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              '선택한 방 인원 (${picked.length}개 방)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [for (final r in picked) ..._roomBlock(r)],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _roomBlock(Room r) {
    final people = store.occupantsOf(r)
      ..sort((a, b) {
        final g = (a.cell ?? a.zone ?? '').compareTo(b.cell ?? b.zone ?? '');
        return g != 0 ? g : a.name.compareTo(b.name);
      });
    final summary = roomGroupSummary(r);
    return [
      Container(
        width: double.infinity,
        color: Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          '${r.roomNo}호  ${store.peakOccupancy(r)}/${r.capacity}'
          '${r.gender == null ? '' : '  ${genderLabel(r.gender!)}'}'
          '${summary.isEmpty ? '' : '   $summary'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      if (people.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 12, 6),
          child: Text('비어 있음', style: TextStyle(color: Colors.grey)),
        )
      else
        for (final a in people)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.name}  ${genderLabel(a.gender)} ${a.age}세'
                    '${(a.zone ?? '').isEmpty ? '' : '   존:${a.zone}'}'
                    '${(a.cell ?? '').isEmpty ? '' : '  셀:${a.cell}'}'
                    '   ${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}',
                  ),
                ),
                IconButton(
                  tooltip: '배정 해제',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  onPressed: () {
                    store.assignAll([a], null);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
    ];
  }

  /// "301-304" 같은 범위로 방을 한 번에 선택한다. (store.parseRoomRange 재사용)
  void _selectRoomRange(List<Room> rooms) {
    final wanted = parseRoomRange(roomRange.text).toSet();
    if (wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('호수를 인식하지 못했습니다. 예: 301-304')),
      );
      return;
    }
    final hit = rooms.where((r) => wanted.contains(r.roomNo)).toList();
    setState(() => selectedRooms.addAll(hit.map((r) => r.id)));
    if (hit.length < wanted.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${hit.length}개 선택 · 없는 호수 ${wanted.length - hit.length}개는 건너뜀',
          ),
        ),
      );
    }
  }

  /// 선택한 인원을 선택한 여러 방에 호수 순으로 채운다.
  /// 어디에 몇 명이 들어가는지 먼저 보여주고 확인받는다.
  Future<void> _assignToRooms(List<Attendee> chosen) async {
    final rooms = store.event.rooms
        .where((r) => selectedRooms.contains(r.id))
        .toList();
    if (rooms.isEmpty) return;

    var plan = distribute(store.event, chosen, rooms);
    var overflow = false;

    if (plan.unplaced.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('자리가 모자랍니다'),
          content: Text(
            '선택한 ${rooms.length}개 방에 ${plan.assignments.length}명까지만 들어갑니다.\n'
            '${plan.unplaced.length}명은 자리가 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'partial'),
              child: const Text('들어가는 만큼만'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'overflow'),
              child: const Text('초과해서 전부 배정'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'overflow') {
        overflow = true;
        plan = distribute(store.event, chosen, rooms, overflow: true);
      }
    }

    // 방별 인원 요약을 보여주고 최종 확인.
    final byRoom = <String, int>{};
    for (final x in plan.assignments) {
      byRoom[x.room.roomNo] = (byRoom[x.room.roomNo] ?? 0) + 1;
    }
    final lines = byRoom.entries.map((e) => '${e.key}호  ${e.value}명').toList()
      ..sort();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${plan.assignments.length}명 배정'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overflow)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '정원을 넘겨 배정합니다.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              for (final l in lines) Text(l),
            ],
          ),
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

    applyAssignments(plan.assignments);
    store.commit();
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
/// 방에 들어있는 그룹(셀 우선, 없으면 존) 별 인원 요약. 예: "에클레시아 4 · 다른셀 2"
String roomGroupSummary(Room room) {
  final counts = <String, int>{};
  for (final a in store.occupantsOf(room)) {
    final key = (a.cell ?? '').isNotEmpty
        ? a.cell!
        : (a.zone ?? '').isNotEmpty
        ? a.zone!
        : '소속없음';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((x, y) => y.value.compareTo(x.value));
  return entries.map((e) => '${e.key} ${e.value}').join(' · ');
}

class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  });
  final Room room;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

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
    final summary = roomGroupSummary(room);
    return SizedBox(
      width: 150,
      child: Material(
        color: color,
        // shape 와 borderRadius 를 같이 주면 Material 이 assert 로 죽는다. shape 만 쓴다.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected
              ? const BorderSide(color: Colors.indigo, width: 3)
              : BorderSide.none,
        ),
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
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.indigo,
                        ),
                      ),
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
                // 누가/어느 그룹이 들어있는지 한 줄로. 클릭 전에도 보이게.
                Text(
                  summary.isEmpty ? '비어 있음' : summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: summary.isEmpty
                        ? Colors.black38
                        : Colors.black.withValues(alpha: 0.7),
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
