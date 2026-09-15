import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../remote.dart';
import '../theme.dart';
import '../models.dart';
import '../store.dart';
import 'gatherings.dart';

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
      // 한 명씩 추가는 [신청·입금]의 [신청 추가]로 한다 — 입금 확인까지 거쳐야 해서.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'paste',
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final added = await pasteDialog(context);
          if (added == null) return;
          store.event.attendees.addAll(added);
          store.commit();
          messenger.showSnackBar(
            SnackBar(content: Text('${added.length}명 등록됨')),
          );
        },
        icon: const Icon(Icons.content_paste),
        label: const Text('붙여넣기 등록'),
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
                Tooltip(
                  message: current.value == null
                      ? '서버에 연결된 집회에서만 쓸 수 있습니다'
                      : '입금이 확인된 신청자를 참석자로 가져옵니다. 여러 번 눌러도 됩니다.',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('신청에서 가져오기'),
                    onPressed: current.value == null
                        ? null
                        : () => importRegistrations(context),
                  ),
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
                    child: Text(
                      '참석자가 없습니다. 신청은 [신청·입금]에서 추가하고, 엑셀 명단은 [붙여넣기 등록]으로 넣으세요.',
                    ),
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
                            for (final e in a.extra.entries)
                              if (e.value.isNotEmpty) '${e.key}:${e.value}',
                          ].join('  '),
                        ),
                        trailing: Text(
                          room == null ? '미배정' : room.label,
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
    // 건물 → 호수 순, 미배정은 맨 뒤
    'room' => switch ((store.roomById(a.roomId), store.roomById(b.roomId))) {
      (final x?, final y?) => byRoomNo(x, y),
      (null, null) => 0,
      (null, _) => 1,
      _ => -1,
    },
    _ => a.name.compareTo(b.name),
  };
}

/// 입금 확인된 신청 → 참석자. 방이 배정된 사람이 빠지게 되면 먼저 보여주고 묻는다.
Future<void> importRegistrations(BuildContext context) async {
  final g = current.value;
  if (g == null) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!await ensureAdmin(context)) return;
  try {
    final regs = await remote.registrations(g.id);
    final gone = store.syncWouldRemove(g, regs);
    if (gone.isNotEmpty && context.mounted) {
      final ok = await confirmDialog(
        context,
        title: '방이 배정된 ${gone.length}명이 빠집니다',
        body:
            '신청이 취소됐거나 입금대기로 되돌려진 사람들입니다. 빼면 방 배정도 풀립니다.\n\n'
            '${gone.take(20).map((a) => '· ${a.name} (${store.roomById(a.roomId)?.label ?? '-'}호)').join('\n')}'
            '${gone.length > 20 ? '\n… 외 ${gone.length - 20}명' : ''}',
        action: '빼고 가져오기',
        danger: true,
      );
      if (!ok) return;
    }
    var keep = true;
    final c = store.syncConflicts(g, regs);
    if ((c.edited.isNotEmpty || c.deleted.isNotEmpty) && context.mounted) {
      final choice = await _askKeepAdminEdits(context, c);
      if (choice == null) return;
      keep = choice;
    }
    final r = store.syncRegistrations(g, regs, keepAdminEdits: keep);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '신청에서 가져옴: 추가 ${r.added} · 변경 ${r.updated} · 제거 ${r.removed}'
          '${r.dayOnly > 0 ? '  (당일 참석 ${r.dayOnly}명은 방이 필요 없어 뺐습니다)' : ''}',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorText(e))));
  }
}

/// 운영자가 직접 고치거나 지운 사람을 신청 내용으로 되돌릴지 묻는다.
/// true = 운영자 수정 유지, false = 신청 내용으로, null = 가져오기 취소.
Future<bool?> _askKeepAdminEdits(
  BuildContext context,
  ({List<Attendee> edited, List<Attendee> deleted}) c,
) {
  String names(List<Attendee> xs) =>
      xs.take(20).map((a) => '· ${a.name}').join('\n') +
      (xs.length > 20 ? '\n… 외 ${xs.length - 20}명' : '');
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('운영자가 고친 참석자가 있습니다'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Text(
            [
              if (c.edited.isNotEmpty)
                '직접 수정한 ${c.edited.length}명 (신청 내용과 다름)\n${names(c.edited)}',
              if (c.deleted.isNotEmpty)
                '직접 삭제한 ${c.deleted.length}명 (신청에는 있음)\n${names(c.deleted)}',
              '운영자가 고친 내용을 그대로 둘까요, 신청 내용으로 되돌릴까요?',
            ].join('\n\n'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('신청 내용으로'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('운영자 수정 유지'),
        ),
      ],
    ),
  );
}

/// 참석자 수정/삭제. 새로 받는 사람은 [신청·입금]의 [신청 추가]로 넣는다.
Future<void> attendeeDialog(BuildContext context, Attendee a) async {
  final name = TextEditingController(text: a.name);
  final age = TextEditingController(text: '${a.age}');
  final phone = TextEditingController(text: a.phone ?? '');
  final cell = TextEditingController(text: a.cell ?? '');
  final zone = TextEditingController(text: a.zone ?? '');
  final note = TextEditingController(text: a.note ?? '');
  var gender = a.gender;
  final messenger = ScaffoldMessenger.of(context);
  // 사용자 정의 항목: 이름 -> 입력칸
  final extras = {
    for (final f in store.event.customFields)
      f: TextEditingController(text: a.extra[f] ?? ''),
  };

  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('참석자 수정'),
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
                if (extras.isNotEmpty) const Divider(height: 24),
                for (final f in store.event.customFields)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: extras[f],
                          decoration: InputDecoration(labelText: f),
                        ),
                      ),
                      IconButton(
                        tooltip: '\'$f\' 항목 이름 바꾸기',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () async {
                          final ok = await renameCustomFieldDialog(context, f);
                          if (ok) setLocal(() {});
                        },
                      ),
                      IconButton(
                        tooltip: '\'$f\' 항목 삭제',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          final ok = await removeCustomFieldDialog(context, f);
                          if (ok) setLocal(() {});
                        },
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('항목 추가'),
                    onPressed: () async {
                      final name = await addCustomFieldDialog(context);
                      if (name == null) return;
                      extras[name] = TextEditingController();
                      setLocal(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
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
  if (action == 'delete') {
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: '참석자 삭제',
      body: "'${a.name}' 님을 참석자에서 삭제합니다. 배정된 방도 풀리고 되돌릴 수 없습니다.",
      action: '삭제',
      danger: true,
    );
    if (ok) store.deleteAttendees([a]);
    return;
  }

  final n = name.text.trim();
  final ageN = int.tryParse(age.text.trim());
  if (n.isEmpty || ageN == null) {
    messenger.showSnackBar(const SnackBar(content: Text('이름과 나이는 필수입니다')));
    return;
  }
  // 입력 검사를 먼저 하고 묻는다 — 확인하고 나서 필수값 오류가 나면 헛걸음이다.
  if (!context.mounted) return;
  final save = await confirmDialog(
    context,
    title: '참석자 수정',
    body: "'$n' 님 정보를 저장합니다.",
    action: '저장',
  );
  if (!save) return;
  String? opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  final extraValues = {
    for (final e in extras.entries)
      if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
  };

  // 신청에서 오는 항목이 실제로 바뀌었을 때만 "운영자가 고침"으로 친다.
  // 기타(note)는 가져오기가 덮어쓰지 않으니 빼고, 그냥 [저장]만 누른 것도 치지 않는다.
  // 안 그러면 입금 확인 때의 자동 가져오기가 그 사람의 신청 변경을 말없이 건너뛴다.
  final changed =
      a.name != n ||
      a.gender != gender ||
      a.age != ageN ||
      a.phone != opt(phone) ||
      a.cell != opt(cell) ||
      a.zone != opt(zone) ||
      !mapEquals(a.extra, extraValues);
  a
    ..name = n
    ..gender = gender
    ..age = ageN
    ..phone = opt(phone)
    ..cell = opt(cell)
    ..zone = opt(zone)
    ..note = opt(note)
    ..extra = extraValues;
  if (changed) a.editedByAdmin = true;
  store.commit();
}

/// 참석자에 새 항목(예: 교회)을 만든다. 만든 이름을 돌려준다.
Future<String?> addCustomFieldDialog(BuildContext context) async {
  final ctl = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('참석자 항목 추가'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '항목 이름',
            helperText: '예: 교회, 직분 — 모든 참석자에게 생깁니다',
          ),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('추가'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  final name = ctl.text.trim();
  if (!store.addCustomField(name)) {
    messenger.showSnackBar(
      SnackBar(content: Text(name.isEmpty ? '이름을 입력하세요' : '이미 있는 항목입니다')),
    );
    return null;
  }
  return name;
}

Future<bool> renameCustomFieldDialog(BuildContext context, String from) async {
  final ctl = TextEditingController(text: from);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('항목 이름 바꾸기'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '새 이름'),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('변경'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  if (!store.renameCustomField(from, ctl.text)) {
    messenger.showSnackBar(const SnackBar(content: Text('바꾸지 못했습니다')));
    return false;
  }
  return true;
}

Future<bool> removeCustomFieldDialog(BuildContext context, String name) async {
  final used = store.event.attendees
      .where((a) => (a.extra[name] ?? '').isNotEmpty)
      .length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("'$name' 항목 삭제"),
      content: Text(
        used == 0 ? '이 항목을 삭제합니다.' : '$used명이 이 항목에 값을 갖고 있습니다. 그 값도 함께 지워집니다.',
      ),
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
  if (ok != true) return false;
  store.removeCustomField(name);
  return true;
}

/// 엑셀에서 복사한 명단을 붙여넣어 참석자로 읽는다. 저장을 누르면 정상 행, 취소면 null.
/// 참석자 화면과 [신청·입금]의 [붙여넣기 추가]가 같이 쓴다.
Future<List<Attendee>?> pasteDialog(
  BuildContext context, {
  String title = '붙여넣기로 참석자 등록',
  String? help,
  bool requirePhone = false,
}) async {
  final text = TextEditingController();
  var columns = [...defaultColumns];
  List<ParsedRow> preview = const [];

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
            requirePhone: requirePhone,
          );
        });
        final good = preview.where((r) => r.ok).length;
        final bad = preview.length - good;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 820,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '엑셀에서 셀 범위를 복사해 그대로 붙여넣으세요 (탭 구분). 컬럼 순서를 아래에서 맞춥니다.',
                ),
                if (help != null) Text(help),
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
                            for (final e in attendeeColumnOptions(
                              store.event,
                            ).entries)
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

  if (ok != true) return null;
  return [for (final r in preview) ?r.attendee];
}
