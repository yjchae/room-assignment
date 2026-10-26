import 'package:flutter/material.dart';

import '../gathering.dart' show mdw;
import '../main.dart';
import '../models.dart';
import '../store.dart' show parseRoomRange;
import '../theme.dart';
import '../widgets/room_board.dart' show RoomBoard, RoomLegend;
import 'attendees.dart' show importRegistrations;

/// 방 관리. 방배정과 같은 보드를 쓰고, 방을 누르면 수정 창이 뜬다.
/// 홈스테이에서는 방 = 가정이고, 신청(입금대기 포함)에서 가져온다.
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = store.event.rooms;
    final homestay = current.value?.isHomestay == true;
    final free = rooms
        .map(store.freeSeats)
        .fold(0, (s, x) => s + (x > 0 ? x : 0));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Wrap(
            spacing: 28,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SectionTitle(
                homestay ? '가정 관리' : '방 관리',
                subtitle: homestay
                    ? '신청이 들어오면 가정이 생깁니다(대기 표시 = 아직 확정 전). 가정을 누르면 정원·기타를 고칠 수 있습니다'
                    : '방을 누르면 수정 · 추가할 때 "301-310" 처럼 범위로 한 번에',
              ),
              _kpi(homestay ? '가정' : '방', '${rooms.length}', homestay ? '곳' : '개'),
              _kpi('총 수용', '${store.totalCapacity}', '명'),
              _kpi('빈자리', '$free', '석'),
              if (homestay)
                OutlinedButton.icon(
                  onPressed: () => importRegistrations(context),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('신청에서 가져오기'),
                ),
              FilledButton.icon(
                onPressed: () => _roomDialog(context),
                icon: Icon(Icons.add, size: 18),
                label: Text(homestay ? '가정 직접 추가' : '방 추가'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: RoomLegend(),
        ),
        RoomBoard(
          rooms: rooms,
          onTap: (r) => _roomDialog(context, r),
          emptyMessage: homestay
              ? '가정이 없습니다. [신청·입금]에서 신청을 확정하면 그 이름으로 가정이 생깁니다.\n'
                    '이미 확정한 신청은 [신청에서 가져오기]로 한 번에 가져옵니다.'
              : '방이 없습니다. [방 추가]로 "301-310" 처럼 범위를 넣으면 한 번에 만들어집니다.\n'
                    '건물이 여러 개면 건물 이름(예: 반석관)도 같이 넣으세요.',
        ),
      ],
    );
  }

  /// 도구 막대 안의 숫자 하나. 카드 안이라 [StatCard] 처럼 따로 면을 두지 않는다.
  Widget _kpi(String label, String value, String unit) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
      const SizedBox(height: 2),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                fontFeatures: tabular,
              ),
            ),
            TextSpan(
              text: ' $unit',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// [room] 이 null 이면 추가(범위 지원), 있으면 수정.
Future<void> _roomDialog(BuildContext context, [Room? room]) async {
  final buildingCtl = TextEditingController(text: room?.building ?? '');
  final noCtl = TextEditingController(text: room?.roomNo ?? '');
  final capCtl = TextEditingController(text: '${room?.capacity ?? 4}');
  final noteCtl = TextEditingController(text: room?.note ?? '');
  String? gender = room?.gender;
  final messenger = ScaffoldMessenger.of(context);
  // 홈스테이는 방이 가정이다 — 이름이 호수가 아니라서 범위(301-310)로 만들지 않는다.
  final homestay = current.value?.isHomestay == true;
  // 날짜 없는 집회는 방(그룹)을 이름으로도 만든다 ('1조', '찬양팀').
  final dateless = current.value?.dateless == true;
  // 일반 집회 방은 쓰는 기간을 정할 수 있다 (PLAN_GATHERING §26). 홈스테이는 신청서의 받는 기간이
  // 기준이고, 날짜 없는 집회와 1박 집회는 나눌 밤이 없다.
  final start = dateOnly(store.event.startDate);
  final end = dateOnly(store.event.endDate);
  final periodable = !homestay && !dateless && store.event.nights.length > 1;
  var limited = periodable && room?.hostFrom != null && room?.hostTo != null;
  var from = limited ? room!.hostFrom! : start;
  var to = limited ? room!.hostTo! : end;

  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(
          room == null
              ? (homestay ? '가정 추가' : '방 추가')
              : '${homestay ? '가정' : '방'} ${room.label} 수정',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // 칸 사이가 붙어 있으면 위 칸의 설명 글과 아래 칸 이름이 겹쳐 보인다.
            spacing: 16,
            children: [
              const SizedBox(height: 4),
              TextField(
                controller: buildingCtl,
                decoration: InputDecoration(
                  labelText: homestay ? '묶음 (선택)' : '건물 (선택)',
                  hintText: homestay ? '예: 서쪽 마을' : '예: 반석관',
                  helperText: homestay
                      ? '가정을 지역·교회로 묶어 보고 싶을 때만 씁니다.'
                      : '건물이 여러 개일 때만. 건물이 다르면 같은 호수도 따로 만들어집니다.',
                  helperMaxLines: 2,
                ),
              ),
              TextField(
                controller: noCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: homestay
                      ? '가정 이름'
                      : dateless
                      ? '방·그룹 이름'
                      : '호수',
                  helperText: homestay
                      ? '보통은 [신청에서 가져오기]로 신청자 이름이 들어옵니다.'
                      : room != null
                      ? null
                      : dateless
                      ? '범위 가능: 301-310 · 이름도 됩니다: 1조, 찬양팀'
                      : '범위 가능: 301-310, 401',
                  helperMaxLines: dateless ? 2 : null,
                ),
              ),
              TextField(
                controller: capCtl,
                decoration: const InputDecoration(labelText: '수용 인원'),
                keyboardType: TextInputType.number,
              ),
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
              if (periodable)
                _periodField(
                  context,
                  limited: limited,
                  from: from,
                  to: to,
                  start: start,
                  end: end,
                  onChanged: (l, f, t) => setLocal(() {
                    limited = l;
                    from = f;
                    to = t;
                  }),
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
  final building = buildingCtl.text.trim().isEmpty
      ? null
      : buildingCtl.text.trim();

  // 집회 전체와 같은 기간은 기간을 안 정한 것과 같다.
  if (limited && from == start && to == end) limited = false;
  final pFrom = limited ? from : null, pTo = limited ? to : null;

  if (room != null) {
    final no = noCtl.text.trim();
    if (no.isEmpty) return;
    final periodChanged =
        periodable && (pFrom != room.hostFrom || pTo != room.hostTo);
    // 이미 배정된 사람의 기간 밖 일정은 떼어 미배정으로 돌린다 — 저장 전에 몇 명인지 묻는다.
    if (periodChanged) {
      final out = store.outsidePeriod(room, pFrom, pTo);
      if (out.isNotEmpty) {
        if (!context.mounted) return;
        if (!await _confirmSplit(context, room, out, from, to)) return;
      }
    }
    room
      ..roomNo = no
      ..building = building
      ..capacity = cap
      ..gender = gender
      ..note = note;
    store.commit();
    if (periodChanged) {
      final n = store.setRoomPeriod(room, pFrom, pTo);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            pFrom == null
                ? '${room.label}호를 집회 전체 기간 쓰도록 바꿨습니다.'
                : '${room.label}호 사용 기간: ${mdw(from)} ~ ${mdw(to)}'
                      '${n == 0 ? '' : ' · $n명의 남은 기간은 미배정입니다 — [방배정]에서 다른 방에 넣어 주세요.'}',
          ),
        ),
      );
    }
    return;
  }

  if (homestay) {
    final no = noCtl.text.trim();
    if (no.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('가정 이름을 입력하세요')));
      return;
    }
    store.addRoom(
      Room(
        id: store.newId(),
        roomNo: no,
        building: building,
        capacity: cap,
        gender: gender,
        note: note,
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text('$no 가정을 추가했습니다.')));
    return;
  }

  final name = noCtl.text.trim();
  if (dateless && name.isEmpty) return;
  final (made, skipped) = store.addRoomRange(
    noCtl.text,
    capacity: cap,
    building: building,
    gender: gender,
    note: note,
    names: dateless,
    from: pFrom,
    to: pTo,
  );
  // 날짜 없는 집회는 호수로 못 읽은 입력('1조')을 이름 방 하나로 만든다.
  if (dateless && name.isNotEmpty && parseRoomRange(name).isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(made > 0 ? '$name 방을 추가했습니다.' : '$name 방이 이미 있습니다.'),
      ),
    );
  } else if (made == 0 && skipped == 0) {
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

/// 방 수정 창의 [사용 기간] 칸: [집회 전체 | 기간 지정] + 들어오는 날·비우는 날.
/// 날짜는 집회 기간([start]~[end]) 안에서만 고른다. 비우는 날은 그날 아침에 나간다(그 밤은 안 쓴다).
Widget _periodField(
  BuildContext context, {
  required bool limited,
  required DateTime from,
  required DateTime to,
  required DateTime start,
  required DateTime end,
  required void Function(bool limited, DateTime from, DateTime to) onChanged,
}) {
  Future<DateTime?> pick(
    DateTime initial,
    DateTime first,
    DateTime last,
  ) async {
    final d = await showDatePicker(
      context: context,
      // 집회 날짜를 나중에 옮기면 저장된 기간이 범위 밖일 수 있다 — 범위 안으로 당긴다.
      initialDate: initial.isBefore(first)
          ? first
          : initial.isAfter(last)
          ? last
          : initial,
      firstDate: first,
      lastDate: last,
    );
    return d == null ? null : dateOnly(d);
  }

  final lastIn = end.subtract(const Duration(days: 1));
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Text('사용 기간  '),
          ...[(false, '집회 전체'), (true, '기간 지정')].map(
            (x) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(x.$2),
                selected: limited == x.$1,
                onSelected: (_) => onChanged(x.$1, from, to),
              ),
            ),
          ),
        ],
      ),
      if (limited) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('들어오는 날'),
          trailing: Text(mdw(from)),
          onTap: () async {
            final d = await pick(from, start, lastIn);
            if (d == null) return;
            onChanged(
              true,
              d,
              to.isAfter(d) ? to : d.add(const Duration(days: 1)),
            );
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('비우는 날'),
          subtitle: Text(
            '${to.difference(from).inDays}박',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(mdw(to)),
          onTap: () async {
            final d = await pick(to, from.add(const Duration(days: 1)), end);
            if (d != null) onChanged(true, from, d);
          },
        ),
        const Text(
          '이 기간에만 사람을 넣습니다. 이미 배정된 사람은 기간 안은 이 방에 그대로 두고, '
          '나머지 기간은 미배정으로 나눠 다른 방에 넣을 수 있게 합니다.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ],
  );
}

/// 사용 기간을 줄이면 기간 밖에도 묵는 [out] 사람들이 나뉜다는 걸 알리고 묻는다.
Future<bool> _confirmSplit(
  BuildContext context,
  Room room,
  List<Attendee> out,
  DateTime from,
  DateTime to,
) async {
  // 기간을 나눈 사람은 조각이 여럿이라도 한 명으로 적는다.
  final names = {for (final a in out) a.personId: a.name}.values.toList();
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('기간 밖에도 묵는 사람이 있습니다'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room.label}호에 배정된 ${names.length}명이 '
                  '${mdw(from)} ~ ${mdw(to)} 밖에도 묵습니다.',
                ),
                const SizedBox(height: 8),
                Text(
                  names.length > 8
                      ? '${names.take(8).join(', ')} 외 ${names.length - 8}명'
                      : names.join(', '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '기간 안은 이 방에 그대로 두고, 나머지 기간은 미배정으로 나눕니다. '
                  '[방배정]이나 [자동배정]에서 다른 방에 넣어 주세요.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
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
              child: const Text('나누고 저장'),
            ),
          ],
        ),
      ) ==
      true;
}
