import 'package:flutter/material.dart';

import '../main.dart';
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
