import 'package:flutter/material.dart';

import '../auto_assign.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/room_board.dart';

// 방 타일은 위젯으로 분리했지만, 이 화면을 쓰는 쪽(현황 화면·테스트)이
// 계속 여기서 가져다 쓰고 있어 그대로 내보낸다.
export '../widgets/room_board.dart' show RoomTile, RoomBoard, RoomLegend;

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

  /// 사용자 정의 항목(교회 등) 값으로 거르는 칸. 어느 항목이든 값이 걸리면 통과.
  final extraQuery = TextEditingController();
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
    for (final c in [name, cell, zone, ageMin, ageMax, roomRange, extraQuery]) {
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
    final xq = extraQuery.text.trim().toLowerCase();
    if (xq.isNotEmpty &&
        !a.extra.values.any((v) => v.toLowerCase().contains(xq)) &&
        !(a.note ?? '').toLowerCase().contains(xq)) {
      return false;
    }
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

    return ColoredBox(
      color: AppColors.bg,
      child: Row(
        children: [
          SizedBox(width: 400, child: _left(filtered, chosen)),
          Expanded(child: _right(chosen)),
        ],
      ),
    );
  }

  // --- 왼쪽: 인원 고르기 -----------------------------------------------------

  Widget _left(List<Attendee> filtered, List<Attendee> chosen) {
    final allSelected =
        filtered.isNotEmpty && filtered.every((a) => selected.contains(a.id));
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('1. 인원 고르기', subtitle: '조건으로 걸러서 한 번에 선택'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _field(name, '이름')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(cell, '셀')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(zone, '존')),
                  ],
                ),
                if (store.event.customFields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _field(
                    extraQuery,
                    '${store.event.customFields.join(' / ')} / 기타',
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _field(ageMin, '나이 ≥')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(ageMax, '나이 ≤')),
                    const SizedBox(width: 10),
                    for (final g in [(null, '전체'), ('M', '남'), ('F', '여')])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(g.$2),
                          selected: gender == g.$1,
                          onSelected: (_) => setState(() => gender = g.$1),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Checkbox(
                      value: unassignedOnly,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => unassignedOnly = v!),
                    ),
                    const Text('미배정만', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    TextButton(
                      onPressed: filtered.isEmpty
                          ? null
                          : () => setState(() {
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
          Container(
            width: double.infinity,
            color: AppColors.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '검색 ${filtered.length}명',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                _CountPill(
                  '선택 ${chosen.length}명',
                  active: chosen.isNotEmpty,
                  onClear: chosen.isEmpty
                      ? null
                      : () => setState(selected.clear),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      '조건에 맞는 인원이 없습니다.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _attendeeRow(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _attendeeRow(Attendee a) {
    final room = store.roomById(a.roomId);
    final on = selected.contains(a.id);
    final sub = [
      if ((a.zone ?? '').isNotEmpty) '존 ${a.zone}',
      if ((a.cell ?? '').isNotEmpty) '셀 ${a.cell}',
      '${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}',
    ].join('  ·  ');

    return InkWell(
      onTap: () =>
          setState(() => on ? selected.remove(a.id) : selected.add(a.id)),
      child: Container(
        color: on ? AppColors.brandSoft : null,
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(
              value: on,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(
                () => v! ? selected.add(a.id) : selected.remove(a.id),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
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
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoomPill(room?.roomNo),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );

  // --- 오른쪽: 방 고르고 배정 ------------------------------------------------

  Widget _right(List<Attendee> chosen) {
    final rooms = [...store.event.rooms]..sort(byRoomNo);
    final picked = rooms.where((r) => selectedRooms.contains(r.id)).toList();
    final seats = picked.fold(
      0,
      (s, r) => s + store.freeSeats(r).clamp(0, 9999),
    );

    return Column(
      children: [
        _toolbar(chosen, picked, seats),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _roomTools(rooms),
                const SizedBox(height: 12),
                RoomBoard(
                  rooms: rooms,
                  selectedIds: selectedRooms,
                  onTap: (r) => setState(
                    () => selectedRooms.contains(r.id)
                        ? selectedRooms.remove(r.id)
                        : selectedRooms.add(r.id),
                  ),
                  onLongPress: (r) => showRoomOccupants(context, r),
                  emptyMessage: '방이 없습니다. [방 관리]에서 먼저 만들어 주세요.',
                ),
                if (picked.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _pickedOccupants(picked),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 고른 방에 누가 들어있는지. 방을 클릭하면 바로 여기에 명단이 뜬다.
  Widget _pickedOccupants(List<Room> picked) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SectionTitle('고른 방 인원 (${picked.length}개 방)'),
          ),
          for (final r in picked) _occupantBlock(r),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _occupantBlock(Room room) {
    final people = store.occupantsOf(room)
      ..sort((a, b) {
        final g = (a.cell ?? a.zone ?? '').compareTo(b.cell ?? b.zone ?? '');
        return g != 0 ? g : a.name.compareTo(b.name);
      });
    final used = store.peakOccupancy(room);
    final st = statusOf(used: used, capacity: room.capacity);
    final groups = store.groupSummary(room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${room.roomNo}호',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              Text(
                '$used/${room.capacity} · ${st.label}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              if (room.gender != null) GenderBadge(room.gender!, dense: true),
              if (groups.isNotEmpty)
                Text(
                  groups,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
            ],
          ),
        ),
        if (people.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 16, 8),
            child: Text(
              '비어 있음',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          )
        else
          for (final a in people)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 8, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${a.name}  ${genderLabel(a.gender)} ${a.age}세'
                      '${(a.zone ?? '').isEmpty ? '' : '   존:${a.zone}'}'
                      '${(a.cell ?? '').isEmpty ? '' : '  셀:${a.cell}'}'
                      '   ${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}',
                      style: const TextStyle(fontSize: 13),
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
      ],
    );
  }

  /// 상단 고정 액션 바. 무엇을 고른 상태인지 + 무엇을 할 수 있는지.
  Widget _toolbar(List<Attendee> chosen, List<Room> picked, int seats) {
    final ready = chosen.isNotEmpty && picked.isNotEmpty;
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SectionTitle('2. 방 고르기'),
          _CountPill('인원 ${chosen.length}명', active: chosen.isNotEmpty),
          _CountPill(
            '방 ${picked.length}개 · 빈자리 $seats',
            active: picked.isNotEmpty,
            onClear: picked.isEmpty
                ? null
                : () => setState(selectedRooms.clear),
          ),
          FilledButton.icon(
            onPressed: ready ? () => _assignToRooms(chosen) : null,
            icon: const Icon(Icons.login, size: 18),
            label: Text('${chosen.length}명 → ${picked.length}개 방 배정'),
          ),
          OutlinedButton.icon(
            onPressed: chosen.isEmpty ? null : () => _setStay(chosen),
            icon: const Icon(Icons.date_range, size: 18),
            label: const Text('체크인/아웃'),
          ),
          OutlinedButton.icon(
            onPressed: chosen.isEmpty
                ? null
                : () {
                    store.assignAll(chosen, null);
                    setState(() {});
                  },
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('배정 해제'),
          ),
        ],
      ),
    );
  }

  /// 방을 고르는 보조 도구: 호수 범위 입력 + 상태별 일괄 선택 + 범례.
  Widget _roomTools(List<Room> rooms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: TextField(
                controller: roomRange,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '호수 범위로 선택',
                  hintText: '301-304, 401',
                ),
                onSubmitted: (_) => _selectRoomRange(rooms),
              ),
            ),
            OutlinedButton(
              onPressed: () => _selectRoomRange(rooms),
              child: const Text('선택'),
            ),
            const SizedBox(width: 4),
            _quickPick('공실 전체', rooms, RoomStatus.empty),
            _quickPick('여유 전체', rooms, RoomStatus.partial),
          ],
        ),
        const SizedBox(height: 10),
        // Row + Spacer 로 두면 창이 좁을 때 범례가 그대로 넘친다. Wrap 으로 접는다.
        const Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RoomLegend(),
            Text(
              '클릭=선택 · 길게 누르면 인원 목록',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickPick(String label, List<Room> rooms, RoomStatus want) {
    final hit = rooms
        .where(
          (r) =>
              statusOf(used: store.peakOccupancy(r), capacity: r.capacity) ==
              want,
        )
        .toList();
    return ActionChip(
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: want.swatch,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      label: Text('$label ${hit.length}'),
      onPressed: hit.isEmpty
          ? null
          : () => setState(() => selectedRooms.addAll(hit.map((r) => r.id))),
    );
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
                    style: TextStyle(color: AppColors.danger),
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
}

/// 개수 표시 알약. 활성이면 브랜드색, 비활성이면 회색.
class _CountPill extends StatelessWidget {
  const _CountPill(this.text, {this.active = false, this.onClear});
  final String text;
  final bool active;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(10, 5, onClear == null ? 10 : 4, 5),
    decoration: BoxDecoration(
      color: active ? AppColors.brandSoft : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: active
            ? AppColors.brand.withValues(alpha: 0.3)
            : AppColors.border,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.brand : AppColors.textMuted,
          ),
        ),
        if (onClear != null)
          IconButton(
            tooltip: '선택 해제',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close),
            color: active ? AppColors.brand : AppColors.textMuted,
            onPressed: onClear,
          ),
      ],
    ),
  );
}

/// 배정된 방 호수. 미배정이면 흐리게.
class _RoomPill extends StatelessWidget {
  const _RoomPill(this.roomNo);
  final String? roomNo;

  @override
  Widget build(BuildContext context) {
    final on = roomNo != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on
            ? AppColors.info.withValues(alpha: 0.12)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? Colors.transparent : AppColors.border),
      ),
      child: Text(
        roomNo ?? '미배정',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: on ? const Color(0xFF0B6A85) : AppColors.textMuted,
        ),
      ),
    );
  }
}

Future<void> showRoomOccupants(BuildContext context, Room room) {
  final list = store.occupantsOf(room)
    ..sort((a, b) => a.name.compareTo(b.name));
  final used = store.peakOccupancy(room);
  final st = statusOf(used: used, capacity: room.capacity);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: st.swatch,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text('${room.roomNo}호'),
          const SizedBox(width: 8),
          Text(
            '$used/${room.capacity} · ${st.label}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
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
                      contentPadding: EdgeInsets.zero,
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
                        '${fmtDate(a.checkIn)}~${fmtDate(a.checkOut)}  ${a.zone ?? ''} ${a.cell ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        tooltip: '배정 해제',
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
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
