import 'package:flutter/material.dart';

import '../gathering.dart' show mdw;
import '../main.dart';
import '../models.dart';
import '../store.dart' show onePerPerson;
import '../responsive.dart';
import '../theme.dart';
import '../widgets/room_board.dart';
import 'assign.dart' show showRoomOccupants, pendingSelection;

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final e = store.event;
    // 사람 단위로 센다 — 기간을 나눈 사람은 조각이 여럿이다.
    // 조각 하나라도 방이 없으면 미배정, 전부 미숙박이면 미숙박, 나머지가 배정완료.
    final unassigned = store.unassigned;
    final total = onePerPerson(e.attendees).length;
    final waiting = unassigned.map((a) => a.personId).toSet();
    final noStay = e.attendees
        .where((a) => !waiting.contains(a.personId))
        .fold(<String, bool>{}, (m, a) {
          m[a.personId] = (m[a.personId] ?? true) && a.noStay;
          return m;
        })
        .values
        .where((v) => v)
        .length;
    final assigned = total - waiting.length - noStay;
    final free = e.rooms
        .map(store.freeSeats)
        .fold(0, (s, x) => s + (x > 0 ? x : 0));
    final compact = windowSizeOf(context).isCompact;
    // 입금 전 신청자도 방을 미리 잡는다. 누가 아직 안 냈는지(독촉할 사람) 바로 보이게.
    final unpaid = e.attendees.where((a) => a.unpaid);
    final unpaidPeople = unpaid.map((a) => a.personId).toSet().length;
    final unpaidInRoom = unpaid
        .where((a) => a.roomId != null && !a.noStay)
        .map((a) => a.personId)
        .toSet()
        .length;

    return ListView(
      padding: EdgeInsets.all(compact ? 12 : 20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatCard('총원', '$total', unit: '명'),
            StatCard('배정완료', '$assigned', unit: '명'),
            if (noStay > 0) StatCard('미숙박', '$noStay', unit: '명'),
            // 색은 손봐야 할 게 남았을 때만.
            StatCard(
              '미배정',
              '${waiting.length}',
              unit: '명',
              color: unassigned.isEmpty ? null : AppColors.warnInk,
            ),
            if (unpaidPeople > 0)
              StatCard(
                '입금대기',
                '$unpaidPeople',
                unit: '명 (배정 $unpaidInRoom)',
                color: AppColors.warnInk,
              ),
            StatCard('총 수용', '${store.totalCapacity}', unit: '명'),
            StatCard('잔여 좌석', '$free', unit: '석'),
          ],
        ),
        const SizedBox(height: 24),
        // 휴대폰은 제목 옆에 범례가 들어갈 폭이 없어서 아래 줄로 내린다.
        if (compact) ...[
          const SectionTitle('전체 구조', subtitle: '타일을 누르면 그 방 인원이 나옵니다'),
          const SizedBox(height: 8),
          const RoomLegend(),
        ] else
          const Row(
            children: [
              Expanded(
                child: SectionTitle('전체 구조', subtitle: '타일을 클릭하면 그 방 인원이 나옵니다'),
              ),
              SizedBox(width: 16),
              RoomLegend(),
            ],
          ),
        const SizedBox(height: 10),
        RoomBoard(rooms: e.rooms, onTap: (r) => showRoomOccupants(context, r)),
        if (e.rooms.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _NightRoster(),
        ],
        const SizedBox(height: 24),
        _SideBySide(
          vertical: compact,
          children: [
            _Panel(
              title: '미배정 인원',
              count: unassigned.length,
              action: unassigned.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () {
                        pendingSelection
                          ..clear()
                          ..addAll(unassigned.map((a) => a.id));
                        tabIndex.value = assignTab;
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
                        if (a.pay != null) ...[
                          const SizedBox(width: 6),
                          PayBadge(a.pay),
                        ],
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
                      tabIndex.value = assignTab;
                    },
                  ),
                if (unassigned.length > 200)
                  const ListTile(dense: true, title: Text('... 이하 생략')),
              ],
            ),
            () {
              final spare =
                  e.rooms.where((r) => store.freeSeats(r) > 0).toList()..sort(
                    (a, b) => store.freeSeats(b).compareTo(store.freeSeats(a)),
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
                            '${r.label}호',
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => showRoomOccupants(context, r),
                    ),
                ],
              );
            }(),
          ],
        ),
      ],
    );
  }
}

/// 패널 두 장을 나란히. 휴대폰은 폭이 모자라 위아래로 쌓는다.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.vertical, required this.children});
  final bool vertical;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => vertical
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(height: 16),
              c,
            ],
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: c),
            ],
          ],
        );
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
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                    color: AppColors.textMuted,
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

/// 일자별 방 인원: 밤 하나를 고르면 방마다 [방 이름·인원 | 그 밤에 묵는 사람] 카드를 층별로 늘어놓는다.
/// 보드 타일은 인원 수만 보여 줘서, 누가 어느 방에 있는지 한눈에 보려고 따로 둔다.
/// 인원은 정원 계산과 같은 규칙([stayMask])으로 센다 — 일정이 집회 밤과 안 겹치는 사람은 모든 밤에 든다.
class _NightRoster extends StatefulWidget {
  const _NightRoster();

  @override
  State<_NightRoster> createState() => _NightRosterState();
}

class _NightRosterState extends State<_NightRoster> {
  /// 고른 밤 (그 밤이 시작되는 날짜). 일정이 바뀌어 없는 밤이면 첫 밤으로.
  DateTime? night;
  bool hideEmpty = false;

  static const _cardWidth = 200.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final e = store.event;
    final nights = e.nights;
    final n = nights.indexOf(night ?? nights.first).clamp(0, nights.length - 1);
    final homestay = current.value?.isHomestay == true;
    // 날짜 없는 집회는 밤이 하나뿐이라 고를 게 없다.
    final oneNight = nights.length == 1 || current.value?.dateless == true;

    List<Attendee> inRoom(Room r) => [
      for (final a in store.occupantsOf(r))
        if (stayMask(a, nights)[n]) a,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final unplaced = onePerPerson(
      e.attendees.where((a) => a.roomId == null && stayMask(a, nights)[n]),
    ).length;

    final floors = byFloorDesc(e.rooms);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SectionTitle(
              homestay ? '일자별 가정 인원' : '일자별 방 인원',
              subtitle: oneNight
                  ? '방마다 배정된 사람이 나옵니다'
                  : '밤을 고르면 그날 밤 방마다 묵는 사람이 나옵니다',
            ),
            if (unplaced > 0)
              Text(
                '이 밤 미배정 $unplaced명',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warnInk,
                ),
              ),
            FilterChip(
              label: Text(homestay ? '빈 가정 숨기기' : '빈 방 숨기기'),
              selected: hideEmpty,
              onSelected: (v) => setState(() => hideEmpty = v),
            ),
          ],
        ),
        if (!oneNight) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final (k, d) in nights.indexed)
                    ButtonSegment(value: k, label: Text('${mdw(d)} 밤')),
                ],
                selected: {n},
                onSelectionChanged: (v) =>
                    setState(() => night = nights[v.first]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final cols = ((box.maxWidth + _gap) / (_cardWidth + _gap))
                .floor()
                .clamp(1, 99);
            final w = (box.maxWidth - _gap * (cols - 1)) / cols;
            final groups = [
              for (final f in floors.entries)
                (
                  f.key,
                  [
                    for (final r in f.value)
                      if (inRoom(r) case final people
                          when !hideEmpty || people.isNotEmpty)
                        (r, people),
                  ],
                ),
            ].where((g) => g.$2.isNotEmpty).toList();
            if (groups.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '이 밤에 묵는 사람이 있는 방이 없습니다.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (g, rooms) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      floorLabel(g),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (final (r, people) in rooms)
                        SizedBox(
                          width: w,
                          child: _RosterCard(room: r, people: people),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 방 하나: 위에 방 이름·인원/정원·상태, 아래에 그 밤에 묵는 사람.
class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.room, required this.people});
  final Room room;
  final List<Attendee> people;

  @override
  Widget build(BuildContext context) {
    final used = people.length;
    final st = statusOf(used: used, capacity: room.capacity);
    return Material(
      color: AppColors.surface,
      // shape 와 borderRadius 를 같이 주면 assert — shape 만 쓴다.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showRoomOccupants(context, room),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: st.fill,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    // 건물·층은 위 묶음 제목에 있다 — 호수만.
                    child: Text(
                      room.roomNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        fontFeatures: tabular,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (room.gender != null) ...[
                    GenderBadge(room.gender!),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '$used/${room.capacity}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                      color: st == RoomStatus.over ? st.ink : AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText(used: used, capacity: room.capacity),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: st.ink,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: people.isEmpty
                  ? const Text(
                      '비어 있음',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final a in people)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    a.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GenderBadge(a.gender),
                                const SizedBox(width: 4),
                                Text(
                                  a.age == 0 ? '' : '${a.age}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFeatures: tabular,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                if (a.pay != null) ...[
                                  const SizedBox(width: 4),
                                  PayBadge(a.pay),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
