import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/room_board.dart' show RoomBoard, RoomLegend;
import 'attendees.dart' show importRegistrations;

/// 방 관리. 방배정과 같은 보드를 쓰고, 방을 누르면 수정 창이 뜬다.
/// 홈스테이에서는 방 = 가정이고, 확정된 신청에서 가져온다.
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
                    ? '확정된 신청에서 가정을 가져옵니다. 가정을 누르면 정원·기타를 고칠 수 있습니다'
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
                  labelText: homestay ? '가정 이름' : '호수',
                  helperText: homestay
                      ? '보통은 [신청에서 가져오기]로 신청자 이름이 들어옵니다.'
                      : room == null
                      ? '범위 가능: 301-310, 401'
                      : null,
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

  if (room != null) {
    final no = noCtl.text.trim();
    if (no.isEmpty) return;
    room
      ..roomNo = no
      ..building = building
      ..capacity = cap
      ..gender = gender
      ..note = note;
    store.commit();
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

  final (made, skipped) = store.addRoomRange(
    noCtl.text,
    capacity: cap,
    building: building,
    gender: gender,
    note: note,
  );
  if (made == 0 && skipped == 0) {
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
