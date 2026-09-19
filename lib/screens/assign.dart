import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auto_assign.dart';
import '../gathering.dart' show mdw;
import '../main.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/room_board.dart';

// 방 타일은 위젯으로 분리했지만, 이 화면을 쓰는 쪽(현황 화면·테스트)이
// 계속 여기서 가져다 쓰고 있어 그대로 내보낸다.
export '../widgets/room_board.dart' show RoomTile, RoomBoard, RoomLegend;

/// Shift 로 치는 키들. 왼쪽/오른쪽 Shift 는 서로 다른 키로 들어온다.
final _shiftKeys = {
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// 배정 화면에서 미리 선택해둘 참석자 (현황 화면에서 넘어올 때 사용).
final pendingSelection = <String>{};

/// 신청서에서 "받는 날"을 못 가져온 가정. 집회 전체를 받는 것처럼 보이면 안 되므로
/// 기간 대신 이 문구를 보여주고 무엇을 눌러야 채워지는지 알려준다.
const _noWindow = '신청서에서 안 가져옴 — [가정 관리]의 [신청에서 가져오기]를 누르세요';

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

  /// Shift+클릭 범위 선택의 시작점(마지막으로 그냥 클릭한 방).
  String? rangeAnchorId;

  /// 방 자리 옮기기 모드. 켜면 타일을 끌어서 실제 건물 배치대로 놓을 수 있다.
  bool editingLayout = false;

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

    // 회색 바탕 위에 [인원 카드 | 방 카드] 두 장.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(width: 320, child: _left(filtered, chosen)),
          ),
          const SizedBox(width: 16),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
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
                  ],
                ),
                const SizedBox(height: 8),
                // 나이 칸과 한 줄에 두면 좁은 카드에서 나이 칸 글자가 사라진다. 따로 한 줄.
                SegmentedButton<String?>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: null, label: Text('전체')),
                    ButtonSegment(value: 'M', label: Text('남')),
                    ButtonSegment(value: 'F', label: Text('여')),
                  ],
                  selected: {gender},
                  onSelectionChanged: (s) => setState(() => gender = s.first),
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
                    itemBuilder: (context, i) =>
                        _attendeeRow(filtered[i], chosen),
                  ),
          ),
        ],
      ),
    );
  }

  /// 참석자 한 줄. 끌어서 방 타일에 놓으면 바로 배정된다 —
  /// 체크된 사람을 끌면 체크된 사람 전부가, 아니면 이 사람만 딸려간다.
  Widget _attendeeRow(Attendee a, List<Attendee> chosen) {
    final on = selected.contains(a.id);
    final people = on ? chosen : [a];
    final row = _attendeeRowBody(a, on);
    final ghost = _DragChip(people);
    // 태블릿은 길게 눌러야 끌린다 — 바로 끌리면 목록을 스크롤하려던 손가락이 사람을 끈다.
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.android => LongPressDraggable<List<Attendee>>(
        data: people,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ghost,
        child: row,
      ),
      _ => Draggable<List<Attendee>>(
        data: people,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ghost,
        child: row,
      ),
    };
  }

  Widget _attendeeRowBody(Attendee a, bool on) {
    final room = store.roomById(a.roomId);
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
            _RoomPill(room?.label),
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _roomTools(rooms),
                const SizedBox(height: 12),
                RoomBoard(
                  rooms: rooms,
                  selectedIds: selectedRooms,
                  onTap: (r) => _pickRoom(r, rooms),
                  onLongPress: (r) => showRoomOccupants(context, r),
                  emptyMessage: '방이 없습니다. [방 관리]에서 먼저 만들어 주세요.',
                  editingLayout: editingLayout,
                  onDropPeople: (room, people) =>
                      _assignToRooms(people, [room], confirm: false),
                  onMove: (room, slot) {
                    store.moveRoom(room, slot, cols: boardColumns);
                    setState(() {});
                  },
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
                '${room.label}호',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
              if ((room.note ?? '').isNotEmpty)
                Text(
                  room.note!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
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
            onPressed: ready ? () => _assignToRooms(chosen, picked) : null,
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

  /// 방을 고르는 보조 도구: 호수 범위 입력 + 상태별 일괄 선택 + 자리 옮기기 + 범례.
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
                  hintText: '301-304, 401 / 반석관 101-104',
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
            const SizedBox(width: 4),
            FilterChip(
              avatar: Icon(
                Icons.open_with,
                size: 16,
                color: editingLayout ? AppColors.brand : AppColors.textMuted,
              ),
              label: const Text('자리 옮기기'),
              selected: editingLayout,
              onSelected: (v) => setState(() => editingLayout = v),
            ),
            if (editingLayout)
              TextButton.icon(
                onPressed: () => _resetLayout(rooms),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('배치 초기화'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Row + Spacer 로 두면 창이 좁을 때 범례가 그대로 넘친다. Wrap 으로 접는다.
        Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const RoomLegend(),
            Text(
              editingLayout
                  ? '타일을 끌어서 실제 건물 자리로 옮기세요 · 다른 방 위에 놓으면 서로 바뀝니다'
                  : '클릭=선택 · Shift+클릭=사이 방까지 한 번에 · 길게 누르면 인원 목록'
                        ' · 왼쪽 인원을 방에 끌어다 놓으면 바로 배정',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  /// 방 타일 클릭. 그냥 클릭하면 하나만 토글하고, Shift 를 누른 채로 클릭하면
  /// 직전에 클릭한 방부터 지금 방까지(호수 순) 사이의 방을 전부 선택한다.
  void _pickRoom(Room room, List<Room> rooms) {
    final anchor = rangeAnchorId;
    if (_shiftHeld && anchor != null && anchor != room.id) {
      final from = rooms.indexWhere((r) => r.id == anchor);
      final to = rooms.indexWhere((r) => r.id == room.id);
      if (from >= 0 && to >= 0) {
        final lo = from < to ? from : to;
        final hi = from < to ? to : from;
        setState(
          () =>
              selectedRooms.addAll(rooms.sublist(lo, hi + 1).map((r) => r.id)),
        );
        return; // 기준점은 그대로 둔다. 범위를 다시 잡을 때 편하다.
      }
    }
    setState(() {
      if (selectedRooms.contains(room.id)) {
        selectedRooms.remove(room.id);
      } else {
        selectedRooms.add(room.id);
      }
      rangeAnchorId = room.id;
    });
  }

  /// 지금 Shift 가 눌려 있는가. 탭 콜백에는 수식키가 안 실려 오므로 키보드 상태를 직접 본다.
  bool get _shiftHeld =>
      HardwareKeyboard.instance.logicalKeysPressed.any(_shiftKeys.contains);

  Future<void> _resetLayout(List<Room> rooms) async {
    if (rooms.every((r) => r.slot == null)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('배치 초기화'),
        content: const Text('손으로 옮긴 방 자리를 모두 지우고 호수 순으로 되돌립니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('되돌리기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    store.resetLayout();
    if (mounted) setState(() {});
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
  /// "반석관 301-304" 처럼 앞에 건물 이름을 붙이면 그 건물 방만 고른다.
  void _selectRoomRange(List<Room> rooms) {
    final m = RegExp(r'^\s*(\D*?)\s*(\d.*)$').firstMatch(roomRange.text);
    final building = m?.group(1)?.trim() ?? '';
    final wanted = parseRoomRange(m?.group(2) ?? '').toSet();
    if (wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('호수를 인식하지 못했습니다. 예: 301-304')),
      );
      return;
    }
    final hit = rooms
        .where(
          (r) =>
              wanted.contains(r.roomNo) &&
              (building.isEmpty || r.building == building),
        )
        .toList();
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
  /// [confirm] 이 false 면(끌어다 놓기) 요약 확인은 건너뛴다. 자리가 모자라면 그래도 묻는다.
  Future<void> _assignToRooms(
    List<Attendee> chosen,
    List<Room> rooms, {
    bool confirm = true,
  }) async {
    if (rooms.isEmpty) return;
    // 홈스테이는 가정 한 곳에 "며칠을" 넣을지부터 고른다.
    if (current.value?.isHomestay == true && rooms.length == 1) {
      return _assignHomestay(chosen, rooms.single);
    }

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
      byRoom[x.room.label] = (byRoom[x.room.label] ?? 0) + 1;
    }
    final lines = byRoom.entries.map((e) => '${e.key}호  ${e.value}명').toList()
      ..sort();
    if (!mounted) return;
    final ok =
        !confirm ||
        await showDialog<bool>(
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
            ) ==
            true;
    if (!ok) return;
    // 홈스테이 가정이 섞여 있으면 신청하지 않은 밤을 여기서도 잡는다.
    if (!await _confirmOutside([
      for (final x in plan.assignments) (x.room, x.attendee),
    ])) {
      return;
    }

    applyAssignments(plan.assignments);
    store.commit();
    if (!confirm && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${plan.assignments.length}명 → ${rooms.first.label}호 배정',
          ),
        ),
      );
    }
    // 배정된 사람은 체크를 푼다. 자리가 모자라 못 들어간 사람은 체크된 채로 남겨
    // 다른 방을 골라 바로 이어서 배정할 수 있게 한다.
    if (mounted) {
      setState(
        () => selected.removeAll(plan.assignments.map((x) => x.attendee.id)),
      );
    }
  }

  /// 홈스테이 배정: 그 가정이 신청한 기간을 보여 주고 며칠을 넣을지 고른다.
  /// [전체 기간 배정] 은 고른 아이들의 일정을 그대로(나누지 않고) 이 집에 넣는다.
  Future<void> _assignHomestay(List<Attendee> chosen, Room room) async {
    if (chosen.isEmpty) return;
    final e = store.event;
    final openFrom = room.hostFrom ?? dateOnly(e.startDate);
    final openTo = room.hostTo ?? dateOnly(e.endDate);
    // 기본값 = 가정이 받을 수 있는 기간과 아이들 일정이 겹치는 만큼.
    var from = chosen
        .map((a) => dateOnly(a.checkIn))
        .fold(openFrom, (x, y) => y.isAfter(x) ? y : x);
    var to = chosen
        .map((a) => dateOnly(a.checkOut))
        .fold(openTo, (x, y) => y.isBefore(x) ? y : x);
    if (!to.isAfter(from)) {
      from = openFrom;
      to = openTo;
    }

    final used = store.peakOccupancy(room);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${room.label} 가정에 배정'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _line(
                  '신청한 날',
                  hostWindowLabel(room).isEmpty ? _noWindow : hostWindowLabel(room),
                ),
                _line(
                  '정원',
                  '$used / ${room.capacity}명'
                      '${room.gender == null ? '' : ' · ${genderLabel(room.gender!)}'}',
                ),
                _line('배정할 아이', '${chosen.length}명'),
                const Divider(height: 24),
                const Text(
                  '며칠을 이 집에서 묵나요?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('들어가는 날'),
                  trailing: Text(fmtDate(from)),
                  onTap: () async {
                    final d = await pickDate(context, from);
                    if (d == null) return;
                    setLocal(() {
                      from = d;
                      if (!to.isAfter(d)) to = d.add(const Duration(days: 1));
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('나오는 날'),
                  subtitle: Text(
                    '${to.difference(from).inDays}박',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(fmtDate(to)),
                  onTap: () async {
                    final d = await pickDate(context, to);
                    if (d != null && d.isAfter(from)) setLocal(() => to = d);
                  },
                ),
                TextButton(
                  onPressed: () => setLocal(() {
                    from = openFrom;
                    to = openTo;
                  }),
                  child: const Text('이 가정이 신청한 기간 그대로'),
                ),
                const SizedBox(height: 4),
                const Text(
                  '고른 기간만 이 집에 넣습니다. 아이의 남는 기간은 미배정으로 남아 '
                  '다른 집에 넣을 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('취소'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('전체 기간 배정'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'range'),
              child: const Text('이 기간만 배정'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || choice == 'cancel') return;

    // 신청하지 않은 밤이 들어가면 먼저 알린다 (중간에 비워 둔 날은 기간만 보면 안 보인다).
    final ok = await _confirmOutside(
      [for (final a in chosen) (room, a)],
      only: choice == 'all' ? null : (from, to),
    );
    if (!ok) return;

    final String done;
    if (choice == 'all') {
      // 아이 일정을 그대로 — 나누지 않는다.
      store.assignAll(chosen, room.id);
      done = '${chosen.length}명을 ${room.label} 가정에 전체 기간으로 배정했습니다.';
    } else {
      final placed = store.assignRange(chosen, room.id, from, to);
      done = placed.isEmpty
          ? '고른 기간에 묵는 아이가 없습니다. 아이 일정을 확인하세요.'
          : '${placed.length}명을 ${room.label} 가정에 '
                '${mdw(from)}~${mdw(to)} (${to.difference(from).inDays}박) 배정했습니다.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    setState(() => selected.removeAll(chosen.map((a) => a.id)));
  }

  /// 배정하려는 (가정, 그 집에서 묵게 될 사람) 짝을 받아, 그 가정이 신청하지 않은 밤이
  /// 끼어 있으면 가정마다 짚어 주고 물어본다. 전부 신청한 날이면 묻지 않고 true.
  ///
  /// 배정으로 사람이 방에 들어가는 길은 전부 이 함수를 지난다 — 가정 한 곳([_assignHomestay])도,
  /// 여러 곳을 골라 한 번에 채우는 길([_assignToRooms])도. 일반 집회 방은 [Room.hostsOn] 이
  /// 늘 참이라 걸리지 않는다.
  ///
  /// [only] 가 있으면 그 기간의 밤만 본다 ([이 기간만 배정]).
  Future<bool> _confirmOutside(
    List<(Room, Attendee)> pairs, {
    (DateTime, DateTime)? only,
  }) async {
    final nights = store.event.nights;
    final bad = <Room, Set<DateTime>>{};
    for (final (room, a) in pairs) {
      final stays = stayMask(a, nights);
      for (var i = 0; i < nights.length; i++) {
        final n = nights[i];
        if (!stays[i] || room.hostsOn(n)) continue;
        if (only case (final f, final t)) {
          if (n.isBefore(f) || !n.isBefore(t)) continue;
        }
        (bad[room] ??= <DateTime>{}).add(n);
      }
    }
    if (bad.isEmpty) return true;
    if (!mounted) return false;
    final rows = [
      for (final e in bad.entries)
        (
          e.key,
          ([...e.value]..sort()).map(mdw).join(', '),
          hostWindowLabel(e.key),
        ),
    ]..sort((x, y) => byRoomNo(x.$1, y.$1));
    final total = bad.values.fold(0, (n, v) => n + v.length);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('신청하지 않은 날입니다'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '가정 ${bad.length}곳에 신청하지 않은 밤 $total박이 들어갑니다.',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  const SizedBox(height: 12),
                  for (final (room, outside, applied) in rows.take(10)) ...[
                    _line('${room.label} · 안 받는 날', outside),
                    _line(
                      '  신청한 날',
                      applied.isEmpty ? _noWindow : applied,
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (rows.length > 10)
                    Text('… 외 ${rows.length - 10}곳'),
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
                child: const Text('그래도 배정'),
              ),
            ],
          ),
        ) ==
        true;
  }

  /// 배정 창의 '항목 — 값' 한 줄.
  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

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
      borderRadius: BorderRadius.circular(Radii.control),
      border: Border.all(
        color: active
            ? AppColors.brand.withValues(alpha: 0.25)
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
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
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

/// 참석자를 끌 때 손끝에 붙는 이름표.
class _DragChip extends StatelessWidget {
  const _DragChip(this.people);
  final List<Attendee> people;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.brand,
    borderRadius: BorderRadius.circular(999),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        people.length == 1
            ? people.first.name
            : '${people.first.name} 외 ${people.length - 1}명',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.surface,
        ),
      ),
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
        color: on ? AppColors.fill : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? AppColors.fill : AppColors.border),
      ),
      child: Text(
        roomNo ?? '미배정',
        style: TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: tabular,
          color: on ? AppColors.text : AppColors.textFaint,
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
          Text('${room.label}호'),
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
