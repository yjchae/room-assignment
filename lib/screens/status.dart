import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// 그 밤에 묵는 사람이 있는 방만.
  bool occupiedOnly = false;

  /// 운영자가 뺀 방 (보기·인쇄에서). 밤을 바꿔도 그대로다. 저장하지 않는다 — 인쇄용 보기일 뿐이다.
  final excluded = <String>{};
  bool printing = false;

  static const _cardWidth = 200.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final e = store.event;
    final nights = e.nights;
    final n = nights.indexOf(night ?? nights.first).clamp(0, nights.length - 1);
    final homestay = current.value?.isHomestay == true;
    final place = homestay ? '가정' : '방';
    // 날짜 없는 집회는 밤이 하나뿐이라 고를 게 없다.
    final oneNight = nights.length == 1 || current.value?.dateless == true;

    List<Attendee> inRoom(Room r) => [
      for (final a in store.occupantsOf(r))
        if (stayMask(a, nights)[n]) a,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final unplaced = onePerPerson(
      e.attendees.where((a) => a.roomId == null && stayMask(a, nights)[n]),
    ).length;

    // 화면과 인쇄가 같은 목록을 쓴다.
    final groups = [
      for (final f in byFloorDesc(e.rooms).entries)
        (
          f.key,
          [
            for (final r in f.value)
              if (!excluded.contains(r.id))
                if (inRoom(r) case final people
                    when !occupiedOnly || people.isNotEmpty)
                  (r, people),
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    final gone = [
      for (final r in [...e.rooms]..sort(byRoomNo))
        if (excluded.contains(r.id)) r,
    ];
    final title = oneNight
        ? '${e.name} · $place 인원'
        : '${e.name} · ${mdw(nights[n])} 밤 $place 인원';

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
                  ? '$place마다 배정된 사람이 나옵니다. 카드의 ×로 인쇄에서 뺄 수 있습니다'
                  : '밤을 고르면 그날 밤 $place마다 묵는 사람이 나옵니다. 카드의 ×로 인쇄에서 뺄 수 있습니다',
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
              label: Text('인원 있는 $place만'),
              selected: occupiedOnly,
              onSelected: (v) => setState(() => occupiedOnly = v),
            ),
            OutlinedButton.icon(
              onPressed: groups.isEmpty
                  ? null
                  : () => showRosterList(context, title, [
                      for (final g in groups) ...g.$2,
                    ]),
              icon: const Icon(Icons.view_list_outlined, size: 18),
              label: const Text('목록 보기'),
            ),
            OutlinedButton.icon(
              onPressed: groups.isEmpty || printing
                  ? null
                  : () => _print(title, groups),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(printing ? '만드는 중…' : '인쇄'),
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
        // 뺀 방: 누르면 되돌린다.
        if (gone.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '뺀 $place ${gone.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              for (final r in gone)
                InputChip(
                  label: Text(r.label),
                  tooltip: '다시 넣기',
                  onDeleted: () => setState(() => excluded.remove(r.id)),
                ),
              TextButton(
                onPressed: () => setState(excluded.clear),
                child: const Text('모두 되돌리기'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '이 밤에 보여 줄 $place이 없습니다.',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final cols = ((box.maxWidth + _gap) / (_cardWidth + _gap))
                  .floor()
                  .clamp(1, 99);
              final w = (box.maxWidth - _gap * (cols - 1)) / cols;
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
                            child: _RosterCard(
                              room: r,
                              people: people,
                              onExclude: () =>
                                  setState(() => excluded.add(r.id)),
                            ),
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

  Future<void> _print(
    String title,
    List<(FloorGroup, List<(Room, List<Attendee>)>)> groups,
  ) async {
    setState(() => printing = true);
    await printHtml(context, title, rosterHtml(title, groups));
    if (mounted) setState(() => printing = false);
  }
}

/// 인쇄용 HTML 을 저장하고 브라우저로 연다 — 열리면 인쇄 창이 바로 뜬다(HTML 의 onload).
/// ponytail: 새 패키지(printing·pdf) 없이 브라우저 인쇄를 빌린다. 웹 앱에서는 파일을 내려받기만
/// 하므로(저장 위치를 모른다) 그 파일을 열어 인쇄한다. 바로 인쇄 창을 띄우려면 `printing` 을 넣는다.
Future<void> printHtml(BuildContext context, String title, String html) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final saved = await FilePicker.saveFile(
      fileName: '${title.replaceAll(RegExp(r'[\\/:*?"<>|·]'), '_')}.html',
      bytes: utf8.encode(html),
      type: FileType.custom,
      allowedExtensions: ['html'],
    );
    if (saved != null) {
      if (!await launchUrl(saved)) {
        messenger.showSnackBar(
          SnackBar(content: Text('저장했습니다. ${saved.toFilePath()} 를 열어 인쇄하세요.')),
        );
      }
    } else if (kIsWeb) {
      messenger.showSnackBar(
        const SnackBar(content: Text('인쇄용 파일을 내려받았습니다. 열면 인쇄 창이 뜹니다.')),
      );
    }
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('인쇄용 파일을 만들지 못했습니다. $err')));
  }
}

/// 방에 든 사람들을 한 줄로: 같은 신청(가족)끼리는 띄어 쓰고 가족 사이는 " / ".
/// 가족 안은 나이 많은 순(보통 부모가 앞), 20세 미만은 이름 뒤에 나이를 괄호로 — "조현호 나윤영 / 드보라(5)".
String rosterNames(List<Attendee> people) {
  final fams = <String, List<Attendee>>{};
  for (final a in people) {
    fams.putIfAbsent(a.registrationId ?? a.personId, () => []).add(a);
  }
  String one(Attendee a) =>
      a.age > 0 && a.age < 20 ? '${a.name}(${a.age})' : a.name;
  return [
    for (final f in fams.values)
      ([...f]..sort((x, y) => y.age.compareTo(x.age))).map(one).join(' '),
  ].join(' / ');
}

/// 방의 구분: 사람들의 존(없으면 셀)을 많은 순으로 '+' 로 잇고 성별을 붙인다 — "B존 여", "A존+C존".
/// 성별은 방 성별, 없으면 모두 같은 성별일 때만.
String rosterGroup(Room room, List<Attendee> people) {
  final counts = <String, int>{};
  for (final a in people) {
    final z = (a.zone ?? '').trim();
    final k = z.isNotEmpty ? z : (a.cell ?? '').trim();
    if (k.isNotEmpty) counts.update(k, (n) => n + 1, ifAbsent: () => 1);
  }
  final keys = counts.keys.toList()
    ..sort((x, y) => counts[y]!.compareTo(counts[x]!));
  final genders = {for (final a in people) a.gender};
  final g = room.gender ?? (genders.length == 1 ? genders.first : null);
  return [
    if (keys.isNotEmpty) keys.join('+'),
    if (g != null && g.isNotEmpty) genderLabel(g),
  ].join(' ');
}

/// 방 칸의 둘째 줄: "(온돌 12인실)" — 방 [기타] 가 있으면 앞에 붙인다.
String roomSizeLabel(Room r) {
  final note = (r.note ?? '').trim();
  return '(${note.isEmpty ? '' : '$note '}${r.capacity}인실)';
}

/// 일자별 방 인원 인쇄용 HTML. 층마다 제목 + 방 카드 격자(방 이름·인원/정원 · 사람 목록).
/// A4 세로에 4칸, 카드가 페이지에 걸쳐 잘리지 않게 한다. 열리면 바로 인쇄 창을 띄운다.
String rosterHtml(
  String title,
  List<(FloorGroup, List<(Room, List<Attendee>)>)> groups,
) {
  const h = HtmlEscape(HtmlEscapeMode.element);
  final total = groups.fold(
    0,
    (s, g) => s + g.$2.fold(0, (t, r) => t + r.$2.length),
  );
  final b = StringBuffer()
    ..write('<!doctype html><html lang="ko"><head><meta charset="utf-8">')
    ..write(
      '<title>${h.convert(title)}</title><style>'
      '@page{size:A4;margin:12mm}'
      'body{font-family:Pretendard,"Apple SD Gothic Neo","Malgun Gothic",sans-serif;'
      'color:#191f28;margin:0;font-size:11pt}'
      'h1{font-size:16pt;margin:0 0 2mm}'
      '.sum{color:#6b7684;font-size:10pt;margin-bottom:4mm}'
      'h2{font-size:12pt;color:#4e5968;margin:5mm 0 2mm;break-after:avoid}'
      '.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:3mm}'
      '.room{border:1px solid #c9cfd6;border-radius:2mm;break-inside:avoid}'
      '.head{display:flex;justify-content:space-between;padding:1.5mm 2.5mm;'
      'background:#f2f4f6;border-bottom:1px solid #c9cfd6;font-weight:700}'
      '.room ol{margin:1.5mm 0;padding:0 2.5mm 0 7mm}'
      '.room li{line-height:1.5}'
      '.meta{color:#6b7684;font-size:9pt}'
      '.empty{color:#8b95a1;padding:1.5mm 2.5mm;font-size:9pt}'
      '</style></head><body onload="print()">',
    )
    ..write('<h1>${h.convert(title)}</h1>')
    ..write(
      '<div class="sum">${groups.fold(0, (s, g) => s + g.$2.length)}개 방 · $total명</div>',
    );
  for (final (g, rooms) in groups) {
    b.write('<h2>${h.convert(floorLabel(g))}</h2><div class="grid">');
    for (final (r, people) in rooms) {
      b.write(
        '<div class="room"><div class="head"><span>${h.convert(r.roomNo)}'
        '${r.gender == null ? '' : ' <span class="meta">${genderLabel(r.gender!)}</span>'}'
        '</span><span>${people.length}/${r.capacity}</span></div>',
      );
      if (people.isEmpty) {
        b.write('<div class="empty">비어 있음</div>');
      } else {
        b.write('<ol>');
        for (final a in people) {
          b.write(
            '<li>${h.convert(a.name)} <span class="meta">'
            '${genderLabel(a.gender)}${a.age == 0 ? '' : ' ${a.age}'}</span></li>',
          );
        }
        b.write('</ol>');
      }
      b.write('</div>');
    }
    b.write('</div>');
  }
  b.write('</body></html>');
  return '$b';
}

/// 방 하나: 위에 방 이름·인원/정원·상태, 아래에 그 밤에 묵는 사람.
class _RosterCard extends StatelessWidget {
  const _RosterCard({
    required this.room,
    required this.people,
    required this.onExclude,
  });
  final Room room;
  final List<Attendee> people;

  /// 이 방을 보기·인쇄에서 뺀다.
  final VoidCallback onExclude;

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
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: '이 방 빼기 (보기·인쇄)',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    iconSize: 16,
                    color: AppColors.textMuted,
                    icon: const Icon(Icons.close),
                    onPressed: onExclude,
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

/// 일자별 방 인원을 표 한 장으로: [번호 | 방(크기) | 구분 | 사람들]. 방 하나가 한 줄이라
/// 한 화면(한 페이지)에서 훑어볼 수 있다. 엑셀로 짜던 방배정표와 같은 모양이다.
Future<void> showRosterList(
  BuildContext context,
  String title,
  List<(Room, List<Attendee>)> rows,
) {
  final people = rows.fold(0, (n, r) => n + r.$2.length);
  return showDialog<void>(
    context: context,
    builder: (context) => WideDialog(
      title: '$title · ${rows.length}개 방 $people명',
      width: 1000,
      height: 640,
      actions: [
        TextButton.icon(
          onPressed: () =>
              printHtml(context, title, rosterListHtml(title, rows)),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('인쇄'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            // 휴대폰에서도 사람 칸이 너무 좁아지지 않게 — 모자라면 옆으로 민다.
            constraints: const BoxConstraints(minWidth: 640, maxWidth: 1000),
            child: _RosterTable(rows),
          ),
        ),
      ),
    ),
  );
}

class _RosterTable extends StatelessWidget {
  const _RosterTable(this.rows);
  final List<(Room, List<Attendee>)> rows;

  static const _head = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
  );

  Widget _cell(Widget child, {bool center = true}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: center ? Center(child: child) : child,
  );

  @override
  Widget build(BuildContext context) {
    final place = current.value?.isHomestay == true ? '' : '호';
    return Table(
      border: TableBorder.all(color: AppColors.border),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FixedColumnWidth(48),
        1: FixedColumnWidth(170),
        2: FixedColumnWidth(120),
        3: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.surfaceAlt),
          children: [
            for (final h in ['번호', '방', '구분', '인원'])
              _cell(Text(h, style: _head)),
          ],
        ),
        for (final (i, (r, people)) in rows.indexed)
          TableRow(
            decoration: BoxDecoration(
              color: i.isOdd
                  ? AppColors.surfaceAlt.withValues(alpha: 0.5)
                  : null,
            ),
            children: [
              _cell(
                Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ),
              _cell(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${r.label}$place',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${roomSizeLabel(r)} · ${people.length}명',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontFeatures: tabular,
                        color: people.length > r.capacity
                            ? AppColors.danger
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _cell(
                Text(
                  rosterGroup(r, people),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _cell(
                Text(
                  people.isEmpty ? '비어 있음' : rosterNames(people),
                  style: TextStyle(
                    height: 1.5,
                    color: people.isEmpty ? AppColors.textFaint : null,
                  ),
                ),
                center: false,
              ),
            ],
          ),
      ],
    );
  }
}

/// [showRosterList] 표의 인쇄용 HTML. A4 세로, 방 한 줄이 페이지에 걸쳐 잘리지 않게 한다.
String rosterListHtml(String title, List<(Room, List<Attendee>)> rows) {
  const h = HtmlEscape(HtmlEscapeMode.element);
  final place = current.value?.isHomestay == true ? '' : '호';
  final people = rows.fold(0, (n, r) => n + r.$2.length);
  final b = StringBuffer()
    ..write('<!doctype html><html lang="ko"><head><meta charset="utf-8">')
    ..write(
      '<title>${h.convert(title)}</title><style>'
      '@page{size:A4;margin:10mm}'
      'body{font-family:Pretendard,"Apple SD Gothic Neo","Malgun Gothic",sans-serif;'
      'color:#191f28;margin:0;font-size:10.5pt}'
      'h1{font-size:15pt;margin:0 0 3mm}'
      'table{width:100%;border-collapse:collapse}'
      'th,td{border:1px solid #8b95a1;padding:2mm 2.5mm;vertical-align:middle}'
      'th{background:#e5e8eb;font-size:10pt}'
      'tr{break-inside:avoid}'
      'tbody tr:nth-child(even){background:#f5f6f8}'
      '.c{text-align:center}.n{width:9mm}.r{width:38mm}.g{width:26mm}'
      '.sub{color:#6b7684;font-size:9pt}.names{line-height:1.6}'
      '</style></head><body onload="print()">',
    )
    ..write('<h1>${h.convert(title)} · ${rows.length}개 방 $people명</h1>')
    ..write(
      '<table><thead><tr><th class="n">번호</th><th class="r">방</th>'
      '<th class="g">구분</th><th>인원</th></tr></thead><tbody>',
    );
  for (final (i, (r, ps)) in rows.indexed) {
    b.write(
      '<tr><td class="c">${i + 1}</td>'
      '<td class="c"><b>${h.convert('${r.label}$place')}</b><br>'
      '<span class="sub">${h.convert(roomSizeLabel(r))} · ${ps.length}명</span></td>'
      '<td class="c">${h.convert(rosterGroup(r, ps))}</td>'
      '<td class="names">${ps.isEmpty ? '<span class="sub">비어 있음</span>' : h.convert(rosterNames(ps))}</td></tr>',
    );
  }
  b.write('</tbody></table></body></html>');
  return '$b';
}
