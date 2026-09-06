import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

/// 타일 사이 간격.
const _gap = 8.0;

/// 타일이 이보다 좁아지면 호수가 안 읽힌다. 이 폭이 안 나오면 보드를 가로로 굴린다.
const _minTile = 74.0;

/// 창이 아주 넓을 때 타일이 흉하게 늘어나는 걸 막는다.
const _maxTile = 150.0;

const _tileHeight = 66.0;

/// 층 격자의 기본 칸 수. 방 자리(slot)가 이 폭을 기준으로 매겨지므로
/// 보드를 그리는 쪽과 자리를 옮기는 쪽이 같은 값을 봐야 한다.
const boardColumns = 10;

/// 방 한 칸. 색 = 상태, 숫자 = 인원/정원, 막대 = 채워진 정도.
///
/// 색만으로 상태를 알려주면 색각 이상이 있는 사람은 못 읽는다. 숫자와 막대를 항상 같이 그린다.
class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.width = 96,
  });

  final Room room;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final used = store.peakOccupancy(room);
    final st = statusOf(used: used, capacity: room.capacity);
    // 좁은 타일에서는 상태 글자를 빼고 색·숫자만 남긴다.
    final showLabel = width >= 92;
    // 타일은 66px 고정이라 그룹 이름을 넣을 자리가 없다. 대신 올려두면 보이게 한다.
    final groups = store.groupSummary(room);

    return Tooltip(
      message:
          '${room.roomNo}호  $used/${room.capacity}  ${st.label}'
          '\n${groups.isEmpty ? '비어 있음' : groups}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: width,
        height: _tileHeight,
        child: Material(
          color: st.fill,
          // shape 와 borderRadius 를 같이 주면 Material 이 assert 로 죽는다. shape 만 쓴다.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.tile),
            side: selected
                ? const BorderSide(color: AppColors.brand, width: 3)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(Radii.tile),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.roomNo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: st.ink,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle,
                          size: 15,
                          color: AppColors.brand,
                        )
                      else if (room.gender != null)
                        GenderBadge(room.gender!, dense: true),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$used',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: st.ink,
                        ),
                      ),
                      Text(
                        '/${room.capacity}',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: st.ink.withValues(alpha: 0.65),
                        ),
                      ),
                      const Spacer(),
                      if (showLabel)
                        Text(
                          st.label,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                            color: st.ink.withValues(alpha: 0.75),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _SeatBar(used: used, capacity: room.capacity, ink: st.ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 정원 대비 채워진 정도. 초과면 끝까지 찬 채로 남는다(숫자와 색이 초과를 말해준다).
class _SeatBar extends StatelessWidget {
  const _SeatBar({
    required this.used,
    required this.capacity,
    required this.ink,
  });
  final int used, capacity;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final ratio = capacity <= 0
        ? 1.0
        : (used / capacity).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 5,
        backgroundColor: ink.withValues(alpha: 0.16),
        valueColor: AlwaysStoppedAnimation(ink.withValues(alpha: 0.72)),
      ),
    );
  }
}

/// 층별로 묶어 그리는 방 보드. 방배정 화면과 현황 화면이 같은 걸 쓴다.
///
/// 높은 층이 위로 온다 — 엘리베이터 층 표시와 같은 순서라 건물이 그대로 보인다.
/// 층 안에서는 [columns] 칸짜리 격자다. 방이 놓이지 않은 칸은 빈 자리로 남아
/// 복도·엘리베이터·계단 같은 실제 건물 모양을 그릴 수 있다.
class RoomBoard extends StatelessWidget {
  const RoomBoard({
    super.key,
    required this.rooms,
    this.selectedIds = const {},
    this.onTap,
    this.onLongPress,
    this.columns = boardColumns,
    this.emptyMessage = '방이 없습니다.',
    this.editingLayout = false,
    this.onMove,
  });

  final List<Room> rooms;
  final Set<String> selectedIds;
  final void Function(Room room)? onTap;
  final void Function(Room room)? onLongPress;

  /// 한 줄에 몇 칸. 저장된 자리 번호가 이 폭을 기준으로 매겨지므로
  /// 창이 좁아져도 줄이지 않는다 (줄이면 배치가 통째로 어긋난다).
  final int columns;
  final String emptyMessage;

  /// 자리 옮기기 모드. 켜면 타일을 끌어서 같은 층의 다른 칸으로 옮길 수 있다.
  final bool editingLayout;

  /// 드롭됐을 때. [slot] 은 그 방이 속한 층 격자에서 0부터 세는 칸 번호.
  final void Function(Room room, int slot)? onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.board,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: rooms.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: const TextStyle(color: AppColors.boardTextDim),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final w = ((c.maxWidth - _gap * (columns - 1)) / columns).clamp(
                  _minTile,
                  _maxTile,
                );
                final rowWidth = w * columns + _gap * (columns - 1);
                final floors = byFloorDesc(rooms);
                final board = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, e) in floors.entries.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      SizedBox(
                        width: rowWidth,
                        child: _FloorHeader(floor: e.key, rooms: e.value),
                      ),
                      const SizedBox(height: 8),
                      _floorGrid(e.key, e.value, w),
                    ],
                  ],
                );
                // 격자 폭은 고정이라 창이 좁으면 넘친다. 잘라내지 말고 가로로 굴린다.
                return rowWidth <= c.maxWidth + 0.5
                    ? board
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: board,
                      );
              },
            ),
    );
  }

  Widget _floorGrid(int? floor, List<Room> floorRooms, double w) {
    final slots = layoutSlots(floorRooms, columns);
    // 옮기는 중에는 맨 아래에 빈 줄을 하나 더 둔다. 새 줄로 내릴 자리가 없으면
    // 아래쪽으로는 아예 옮길 수가 없다.
    if (editingLayout) {
      slots.addAll(List<Room?>.filled(columns, null));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row * columns < slots.length; row++) ...[
          if (row > 0) const SizedBox(height: _gap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = row * columns; i < (row + 1) * columns; i++) ...[
                if (i > row * columns) const SizedBox(width: _gap),
                _slot(floor, slots[i], i, w),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _slot(int? floor, Room? room, int index, double w) {
    final tile = room == null
        ? null
        : RoomTile(
            room: room,
            width: w,
            selected: selectedIds.contains(room.id),
            onTap: onTap == null ? null : () => onTap!(room),
            onLongPress: onLongPress == null ? null : () => onLongPress!(room),
          );

    if (!editingLayout || onMove == null) {
      return SizedBox(
        width: w,
        height: _tileHeight,
        child: tile, // 빈 칸은 그대로 빈 자리로 남는다
      );
    }

    final target = _DropSlot(
      width: w,
      // 층마다 자리 번호가 따로라 다른 층 방은 받지 않는다.
      accepts: (r) => r.floor == floor && !(room != null && room.id == r.id),
      onAccept: (r) => onMove!(r, index),
      child: tile,
    );
    if (room == null) return target;

    return Draggable<Room>(
      data: room,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragGhost(room: room, width: w),
      childWhenDragging: SizedBox(
        width: w,
        height: _tileHeight,
        child: const _EmptySlot(hint: false),
      ),
      child: target,
    );
  }
}

/// 옮기기 모드에서 방 하나가 놓일 수 있는 칸.
class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.width,
    required this.accepts,
    required this.onAccept,
    this.child,
  });

  final double width;
  final bool Function(Room) accepts;
  final void Function(Room) onAccept;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Room>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return SizedBox(
          width: width,
          height: _tileHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child ?? const _EmptySlot(hint: true),
              if (hot)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(Radii.tile),
                    border: Border.all(color: AppColors.brand, width: 2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 빈 칸 표시. 옮기는 중에만 테두리를 보여준다(평소엔 건물 여백이라 아무것도 안 그린다).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.hint});
  final bool hint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: hint ? AppColors.boardLine.withValues(alpha: 0.25) : null,
      borderRadius: BorderRadius.circular(Radii.tile),
      border: Border.all(color: AppColors.boardLine),
    ),
  );
}

/// 끌고 다니는 동안 손끝에 붙는 타일.
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.room, required this.width});
  final Room room;
  final double width;

  @override
  Widget build(BuildContext context) => Transform.translate(
    // 포인터 기준이라 손끝이 타일 가운데 오도록 민다.
    offset: Offset(-width / 2, -_tileHeight / 2),
    child: Material(
      type: MaterialType.transparency,
      child: Opacity(
        opacity: 0.9,
        child: RoomTile(room: room, width: width),
      ),
    ),
  );
}

class _FloorHeader extends StatelessWidget {
  const _FloorHeader({required this.floor, required this.rooms});
  final int? floor;
  final List<Room> rooms;

  @override
  Widget build(BuildContext context) {
    final used = rooms.fold(0, (s, r) => s + store.peakOccupancy(r));
    final cap = rooms.fold(0, (s, r) => s + r.capacity);
    return Row(
      children: [
        Text(
          floor == null ? '기타' : '$floor층',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.boardText,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${rooms.length}실 · $used/$cap명',
          style: const TextStyle(fontSize: 11, color: AppColors.boardTextDim),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: AppColors.boardLine, height: 1)),
      ],
    );
  }
}

/// 색이 뭘 뜻하는지. 보드를 쓰는 화면은 이걸 같이 둔다.
class RoomLegend extends StatelessWidget {
  const RoomLegend({super.key, this.onDark = false});

  /// 어두운 보드 위에 올릴 때 글자색을 바꾼다.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? AppColors.boardText : AppColors.textMuted;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final s in RoomStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.swatch,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                s.label,
                style: TextStyle(
                  fontSize: 12,
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 층별로 묶는다. 높은 층이 앞, 층 안에서는 호수 오름차순. 층 없는 방(비숫자 호수)은 맨 뒤.
Map<int?, List<Room>> byFloorDesc(List<Room> rooms) {
  final sorted = [...rooms]..sort(byRoomNo);
  final map = <int?, List<Room>>{};
  for (final r in sorted) {
    map.putIfAbsent(r.floor, () => []).add(r);
  }
  final keys = map.keys.toList()
    ..sort((a, b) => (b ?? -9999).compareTo(a ?? -9999));
  return {for (final k in keys) k: map[k]!};
}
