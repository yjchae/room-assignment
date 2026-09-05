import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../models.dart';
import '../store.dart';


class AttendeesScreen extends StatefulWidget {
  const AttendeesScreen({super.key});

  @override
  State<AttendeesScreen> createState() => _AttendeesScreenState();
}

class _AttendeesScreenState extends State<AttendeesScreen> {
  String query = '';
  String sortKey = 'name';

  @override
  Widget build(BuildContext context) {
    final list = store.search(query)..sort(_cmp);
    return Scaffold(
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'paste',
            onPressed: () => _pasteDialog(context),
            icon: const Icon(Icons.content_paste),
            label: const Text('붙여넣기 등록'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'one',
            onPressed: () => attendeeDialog(context),
            child: const Icon(Icons.person_add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '이름 / 셀 / 존 / 전화 검색',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: sortKey,
                  onChanged: (v) => setState(() => sortKey = v!),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('이름순')),
                    DropdownMenuItem(value: 'age', child: Text('나이순')),
                    DropdownMenuItem(value: 'cell', child: Text('셀순')),
                    DropdownMenuItem(value: 'zone', child: Text('존순')),
                    DropdownMenuItem(value: 'room', child: Text('방순')),
                  ],
                ),
                const SizedBox(width: 12),
                Text('${list.length} / ${store.event.attendees.length}명'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('참석자가 없습니다. [붙여넣기 등록]을 눌러 엑셀에서 복사해 붙여넣으세요.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = list[i];
                      final room = store.roomById(a.roomId);
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${a.name}  ${genderLabel(a.gender)} ${a.age}세',
                        ),
                        subtitle: Text(
                          [
                            if ((a.zone ?? '').isNotEmpty) '존:${a.zone}',
                            if ((a.cell ?? '').isNotEmpty) '셀:${a.cell}',
                            if ((a.phone ?? '').isNotEmpty) a.phone!,
                            if ((a.note ?? '').isNotEmpty) a.note!,
                          ].join('  '),
                        ),
                        trailing: Text(
                          room == null ? '미배정' : room.roomNo,
                          style: TextStyle(
                            color: room == null ? Colors.grey : Colors.indigo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () => attendeeDialog(context, a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  int _cmp(Attendee a, Attendee b) => switch (sortKey) {
    'age' => b.age.compareTo(a.age),
    'cell' => (a.cell ?? '').compareTo(b.cell ?? ''),
    'zone' => (a.zone ?? '').compareTo(b.zone ?? ''),
    'room' => (store.roomById(a.roomId)?.roomNumber ?? 999999).compareTo(
      store.roomById(b.roomId)?.roomNumber ?? 999999,
    ),
    _ => a.name.compareTo(b.name),
  };
}

/// 개별 추가/수정/삭제.
Future<void> attendeeDialog(BuildContext context, [Attendee? a]) async {
  final name = TextEditingController(text: a?.name ?? '');
  final age = TextEditingController(text: a == null ? '' : '${a.age}');
  final phone = TextEditingController(text: a?.phone ?? '');
  final cell = TextEditingController(text: a?.cell ?? '');
  final zone = TextEditingController(text: a?.zone ?? '');
  final note = TextEditingController(text: a?.note ?? '');
  var gender = a?.gender ?? 'M';
  final messenger = ScaffoldMessenger.of(context);

  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(a == null ? '참석자 추가' : '참석자 수정'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '이름 *'),
                ),
                Row(
                  children: [
                    const Text('성별 * '),
                    ...[('M', '남'), ('F', '여')].map(
                      (g) => Padding(
                        padding: const EdgeInsets.all(4),
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
                  controller: age,
                  decoration: const InputDecoration(labelText: '나이 *'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: '전화'),
                ),
                TextField(
                  controller: cell,
                  decoration: const InputDecoration(labelText: '셀'),
                ),
                TextField(
                  controller: zone,
                  decoration: const InputDecoration(labelText: '존'),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '기타'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (a != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
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
  if (action == 'delete' && a != null) {
    store.deleteAttendees([a]);
    return;
  }

  final n = name.text.trim();
  final ageN = int.tryParse(age.text.trim());
  if (n.isEmpty || ageN == null) {
    messenger.showSnackBar(const SnackBar(content: Text('이름과 나이는 필수입니다')));
    return;
  }
  String? opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  if (a == null) {
    store.event.attendees.add(
      Attendee(
        id: store.newId(),
        name: n,
        gender: gender,
        age: ageN,
        phone: opt(phone),
        cell: opt(cell),
        zone: opt(zone),
        note: opt(note),
        checkIn: store.event.startDate,
        checkOut: store.event.endDate,
      ),
    );
  } else {
    a
      ..name = n
      ..gender = gender
      ..age = ageN
      ..phone = opt(phone)
      ..cell = opt(cell)
      ..zone = opt(zone)
      ..note = opt(note);
  }
  store.commit();
}

Future<void> _pasteDialog(BuildContext context) async {
  final text = TextEditingController();
  var columns = [...defaultColumns];
  List<ParsedRow> preview = const [];
  final messenger = ScaffoldMessenger.of(context);

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        void reparse() => setLocal(() {
          preview = parseAttendeeText(
            text.text,
            columns: columns,
            checkIn: store.event.startDate,
            checkOut: store.event.endDate,
            newId: store.newId,
          );
        });
        final good = preview.where((r) => r.ok).length;
        final bad = preview.length - good;
        return AlertDialog(
          title: const Text('붙여넣기로 참석자 등록'),
          content: SizedBox(
            width: 820,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '엑셀에서 셀 범위를 복사해 그대로 붙여넣으세요 (탭 구분). 컬럼 순서를 아래에서 맞춥니다.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          initialValue: columns[i],
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: '${i + 1}번째 열',
                          ),
                          items: [
                            for (final e in attendeeFields.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (v) {
                            columns[i] = v!;
                            reparse();
                          },
                        ),
                      ),
                    IconButton(
                      tooltip: '열 추가',
                      onPressed: () {
                        columns.add('skip');
                        reparse();
                      },
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: '열 제거',
                      onPressed: columns.length <= 1
                          ? null
                          : () {
                              columns.removeLast();
                              reparse();
                            },
                      icon: const Icon(Icons.remove),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 130,
                  child: TextField(
                    controller: text,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '홍길동\t남\t34\t010-...\t1셀\tA존',
                    ),
                    onChanged: (_) => reparse(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '정상 $good행 · 오류 $bad행 (오류 행은 저장 시 건너뜁니다)',
                  style: TextStyle(
                    color: bad > 0 ? Colors.red : Colors.green.shade800,
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: preview.length,
                    itemBuilder: (context, i) {
                      final r = preview[i];
                      return Container(
                        color: r.ok ? null : Colors.red.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${r.lineNo}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                            Expanded(child: Text(r.cells.join(' | '))),
                            if (!r.ok)
                              Text(
                                r.error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
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
              onPressed: good == 0 ? null : () => Navigator.pop(context, true),
              child: Text('$good명 저장'),
            ),
          ],
        );
      },
    ),
  );

  if (ok != true) return;
  final added = preview.where((r) => r.ok).map((r) => r.attendee!).toList();
  store.event.attendees.addAll(added);
  store.commit();
  messenger.showSnackBar(SnackBar(content: Text('${added.length}명 등록됨')));
}
