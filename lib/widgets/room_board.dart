import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

/// 타일 사이 간격.
const _gap = 8.0;

/// 타일이 이보다 좁아지면 호수가 안 읽힌다. 이 폭을 못 지키면 칸 수를 줄인다.
const _minTile = 74.0;

/// 창이 아주 넓을 때 타일이 흉하게 늘어나는 걸 막는다.
const _maxTile = 150.0;

const _tileHeight = 66.0;

/// 요청 칸 수([want])로 나눴을 때 타일이 [_minTile] 보다 좁아지면 칸을 줄인다.
int fitColumns(double width, int want) {
  var cols = want;
  while (cols > 2 && (width - _gap * (cols - 1)) / cols < _minTile) {
    cols--;
  }
  return cols;
}

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
class RoomBoard extends StatelessWidget {
  const RoomBoard({
    super.key,
    required this.rooms,
    this.selectedIds = const {},
    this.onTap,
    this.onLongPress,
    this.columns = 10,
    this.emptyMessage = '방이 없습니다.',
  });

  final List<Room> rooms;
  final Set<String> selectedIds;
  final void Function(Room room)? onTap;
  final void Function(Room room)? onLongPress;

  /// 한 줄에 몇 칸. 폭이 모자라면 자동으로 줄어든다.
  final int columns;
  final String emptyMessage;

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
                final cols = fitColumns(c.maxWidth, columns);
                final w = ((c.maxWidth - _gap * (cols - 1)) / cols).clamp(
                  _minTile,
                  _maxTile,
                );
                // 타일 폭에 상한이 걸리면 Wrap 이 한 줄에 11개, 12개씩 밀어 넣는다.
                // 줄 폭을 딱 cols 개로 잘라서 "한 줄 = cols 개"를 지킨다.
                final rowWidth = w * cols + _gap * (cols - 1);
                final floors = byFloorDesc(rooms);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, e) in floors.entries.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _FloorHeader(floor: e.key, rooms: e.value),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: rowWidth,
                        child: Wrap(
                          spacing: _gap,
                          runSpacing: _gap,
                          children: [
                            for (final r in e.value)
                              RoomTile(
                                room: r,
                                width: w,
                                selected: selectedIds.contains(r.id),
                                onTap: onTap == null ? null : () => onTap!(r),
                                onLongPress: onLongPress == null
                                    ? null
                                    : () => onLongPress!(r),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
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
