import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gathering.dart' show mdw;
import '../main.dart';
import '../models.dart';
import '../theme.dart';

/// 타일 사이 간격.
const _gap = 6.0;

/// 타일이 이보다 좁아지면 호수가 안 읽힌다. 이 폭이 안 나오면 보드를 가로로 굴린다.
const _minTile = 74.0;

/// 창이 아주 넓을 때 타일이 흉하게 늘어나는 걸 막는다.
const _maxTile = 150.0;

/// 호수 · 기타 한 줄 · 상태/인원이 들어가는 높이.
const _tileHeight = 76.0;

/// 층 번호를 적는 왼쪽 칸 폭. 방 격자는 이 오른쪽에 붙는다.
const _gutter = 60.0;

/// 층 격자의 기본 칸 수. 방 자리(slot)가 이 폭을 기준으로 매겨지므로
/// 보드를 그리는 쪽과 자리를 옮기는 쪽이 같은 값을 봐야 한다.
const boardColumns = 10;

/// 홈스테이 가정이 신청서에서 고른 "받는 날". 중간에 안 받는 밤이 있으면
/// 기간 대신 날짜를 하나씩 적는다 (기간으로 적으면 빈 날이 감춰진다).
/// 신청서에 기간이 없는 방(일반 집회)은 빈 문자열.
String hostWindowLabel(Room room) {
  final ns = room.hostNightList;
  if (ns.isEmpty) return '';
  final gapless = room.hostNights == null;
  return gapless
      ? '${mdw(ns.first)} ~ ${mdw(room.hostTo!)} (${ns.length}박)'
      : '${ns.map(mdw).join(', ')} (${ns.length}박)';
}

/// 방 한 칸. 바탕색 = 상태, 글자 = 상태("2자리"·"1명 초과"), 숫자 = 인원/정원.
///
/// 색만으로 상태를 알려주면 색각 이상이 있는 사람은 못 읽는다. 상태는 항상 글자로도 적는다.
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
    // 타일 높이가 고정이라 그룹 이름을 넣을 자리가 없다. 대신 올려두면 보이게 한다.
    final groups = store.groupSummary(room);
    final note = room.note ?? '';

    final homestay = current.value?.isHomestay == true;
    // 홈스테이는 "언제 받을 수 있는 집인지"가 배정의 첫 기준이라 툴팁에 같이 적는다.
    final label = homestay ? hostWindowLabel(room) : '';
    final window = label.isEmpty ? '' : '\n신청한 날 $label';
    return Tooltip(
      message:
          '${room.label}${homestay ? '' : '호'}'
          '  $used/${room.capacity}  ${st.label}$window'
          '\n${groups.isEmpty ? '비어 있음' : groups}'
          '${note.isEmpty ? '' : '\n$note'}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: width,
        height: _tileHeight,
        child: Material(
          color: selected ? AppColors.brandSoft : st.fill,
          // shape 와 borderRadius 를 같이 주면 Material 이 assert 로 죽는다. shape 만 쓴다.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.tile),
            side: selected
                ? const BorderSide(color: AppColors.brand, width: 1.5)
                // 빈 방은 흰 보드 위 흰 타일이라 테두리로만 보인다.
                : st == RoomStatus.empty
                ? const BorderSide(color: AppColors.border, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(Radii.tile),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
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
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            fontFeatures: tabular,
                            color: AppColors.text,
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
                        Text(
                          genderLabel(room.gender!),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  // 방 관리의 [기타]. 길면 잘리고 전체는 툴팁에 나온다.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // Flexible + Spacer 로 두면 남는 폭을 반씩 나눠 가져 "2…" 로 잘린다.
                      Expanded(
                        child: Text(
                          // 좁은 타일(방배정)에선 "1명 초과" 가 잘린다. 몇 명 넘었는지는 옆 숫자가 말해 준다.
                          st == RoomStatus.over && width < 96
                              ? st.label
                              : statusText(used: used, capacity: room.capacity),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabular,
                            color: st.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$used/${room.capacity}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabular,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 건물·층별로 묶어 그리는 방 보드. 방배정 화면과 현황 화면이 같은 걸 쓴다.
///
/// 높은 층이 위로 온다 — 엘리베이터 층 표시와 같은 순서라 건물이 그대로 보인다.
/// 한 층은 [왼쪽 층 번호 | 방 격자] 한 줄이고, 층과 층 사이는 선으로 나눈다.
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
    this.onDropPeople,
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

  /// 참석자를 방 타일에 끌어다 놓았을 때. 자리 옮기기 모드에서는 받지 않는다.
  final void Function(Room room, List<Attendee> people)? onDropPeople;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: rooms.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final w =
                    ((c.maxWidth - _gutter - _gap * (columns - 1)) / columns)
                        .clamp(_minTile, _maxTile);
                final rowWidth = _gutter + w * columns + _gap * (columns - 1);
                final floors = byFloorDesc(rooms);
                final keys = floors.keys.toList();
                final board = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, e) in floors.entries.indexed) ...[
                      if (i > 0)
                        SizedBox(width: rowWidth, child: const Divider()),
                      // 건물이 바뀌는 첫 층 위에 건물 이름을 보드 폭 한 줄로.
                      // 층 칸(폭 60)에 넣으면 "반석관 - 예배실" 같은 긴 이름이 안 읽힌다.
                      if (e.key.building != null &&
                          (i == 0 || keys[i - 1].building != e.key.building))
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: rowWidth,
                            child: Text(
                              e.key.building!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _gutter,
                              child: Padding(
                                // 긴 건물 이름이 첫 방 타일에 붙지 않게.
                                padding: const EdgeInsets.only(right: 8),
                                child: _FloorHeader(
                                  group: e.key,
                                  rooms: e.value,
                                ),
                              ),
                            ),
                            _floorGrid(e.key, e.value, w),
                          ],
                        ),
                      ),
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

  Widget _floorGrid(FloorGroup group, List<Room> floorRooms, double w) {
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
                _slot(group, slots[i], i, w),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _slot(FloorGroup group, Room? room, int index, double w) {
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
      if (room != null && onDropPeople != null) {
        return _DropSlot<List<Attendee>>(
          width: w,
          accepts: (people) => people.isNotEmpty,
          onAccept: (people) => onDropPeople!(room, people),
          child: tile,
        );
      }
      return SizedBox(
        width: w,
        height: _tileHeight,
        child: tile, // 빈 칸은 그대로 빈 자리로 남는다
      );
    }

    final target = _DropSlot<Room>(
      width: w,
      // 건물·층마다 자리 번호가 따로라 다른 건물·층 방은 받지 않는다.
      accepts: (r) =>
          r.floorGroup == group && !(room != null && room.id == r.id),
      onAccept: (r) => onMove!(r, index),
      child: tile,
    );
    if (room == null) return target;

    final ghost = _DragGhost(room: room, width: w);
    final gap = SizedBox(
      width: w,
      height: _tileHeight,
      child: const _EmptySlot(hint: false),
    );
    // 태블릿은 길게 눌러야 끌린다 — 바로 끌리면 보드를 스크롤하려던 손가락이 방을 옮긴다.
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => LongPressDraggable<Room>(
        data: room,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ghost,
        childWhenDragging: gap,
        child: target,
      ),
      _ => Draggable<Room>(
        data: room,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ghost,
        childWhenDragging: gap,
        child: target,
      ),
    };
  }
}

/// 끌어온 것(옮기는 방, 또는 배정할 참석자들)이 놓일 수 있는 칸.
class _DropSlot<T extends Object> extends StatelessWidget {
  const _DropSlot({
    required this.width,
    required this.accepts,
    required this.onAccept,
    this.child,
  });

  final double width;
  final bool Function(T) accepts;
  final void Function(T) onAccept;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<T>(
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
                    color: AppColors.brand.withValues(alpha: 0.16),
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
      color: hint ? AppColors.surfaceAlt : null,
      borderRadius: BorderRadius.circular(Radii.tile),
      border: Border.all(color: AppColors.border),
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

/// 층 줄 왼쪽의 층 표시. [큰 층 숫자] → [방 수·인원].
/// 건물 이름은 여기 넣지 않는다 — [RoomBoard] 가 그 건물 첫 층 위에 한 줄로 크게 적는다.
class _FloorHeader extends StatelessWidget {
  const _FloorHeader({required this.group, required this.rooms});
  final FloorGroup group;
  final List<Room> rooms;

  static const _small = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  @override
  Widget build(BuildContext context) {
    final used = rooms.fold(0, (s, r) => s + store.peakOccupancy(r));
    final cap = rooms.fold(0, (s, r) => s + r.capacity);
    final f = group.floor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (f != null)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$f',
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    fontFeatures: tabular,
                    color: AppColors.text,
                  ),
                ),
                const TextSpan(text: '층', style: _small),
              ],
            ),
          )
        else
          Text(
            current.value?.isHomestay == true ? '가정' : '기타',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '${rooms.length}실\n$used/$cap명',
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.45,
            fontFeatures: tabular,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// 색이 뭘 뜻하는지. 보드를 쓰는 화면은 이걸 같이 둔다.
class RoomLegend extends StatelessWidget {
  const RoomLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final s in RoomStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: s.swatch,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                s.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 건물·층별로 묶는다. 건물 이름 순(건물 없는 방이 먼저), 건물 안에서는 높은 층이 앞,
/// 층 안에서는 호수 오름차순. 층 없는 방(비숫자 호수)은 그 건물의 맨 뒤.
Map<FloorGroup, List<Room>> byFloorDesc(List<Room> rooms) {
  final sorted = [...rooms]..sort(byRoomNo);
  final map = <FloorGroup, List<Room>>{};
  for (final r in sorted) {
    map.putIfAbsent(r.floorGroup, () => []).add(r);
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      final bd = (a.building ?? '').compareTo(b.building ?? '');
      return bd != 0 ? bd : (b.floor ?? -9999).compareTo(a.floor ?? -9999);
    });
  return {for (final k in keys) k: map[k]!};
}

/// "반석관 3층" / "3층" / "반석관" / "기타"
String floorLabel(FloorGroup g) {
  final parts = [?g.building, if (g.floor != null) '${g.floor}층'];
  return parts.isEmpty ? '기타' : parts.join(' ');
}
