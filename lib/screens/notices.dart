import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gathering.dart';
import '../main.dart';
import '../remote.dart';
import '../theme.dart';
import 'gatherings.dart';

/// 공지 등록과 카카오톡 전달. 기획은 PLAN_NOTICE.md.
///
/// 왼쪽 목록에서 공지를 고르고 오른쪽에서 고친다. 저장한 공지는 그 아래 [보내기] 카드에서
/// 대상을 골라 메시지로 만든다. **실제 전송은 운영자가 카카오톡에 붙여넣어서 한다** —
/// 전화번호만으로 카카오톡을 보내는 길은 알림톡뿐이고 그건 별도 계약이 필요하다(PLAN_NOTICE.md §1).
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  List<Notice>? items;
  List<Registration> regs = [];
  String? error;
  bool loading = false;
  bool saving = false;

  /// 고치는 중인 사본. 저장 전까지 서버·[items] 와 다를 수 있다.
  Notice? draft;
  final title = TextEditingController();
  final body = TextEditingController();

  NoticeTarget target = NoticeTarget.all;
  List<NoticeSend> sends = [];

  @override
  void initState() {
    super.initState();
    signInCount.addListener(_onSignIn);
    if (current.value != null && remote.signedIn) _load();
  }

  @override
  void dispose() {
    signInCount.removeListener(_onSignIn);
    title.dispose();
    body.dispose();
    super.dispose();
  }

  void _onSignIn() {
    if (!mounted) return;
    if (remote.signedIn) {
      _load();
    } else {
      setState(() => items = null);
    }
  }

  Future<void> _load() async {
    final g = current.value;
    if (g == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // 대상 인원수를 세려면 신청 목록도 있어야 한다.
      final ns = sortedNotices(await remote.notices(g.id));
      final rs = await remote.registrations(g.id);
      if (!mounted) return;
      items = ns;
      regs = rs;
      // 고쳐 두던 공지가 목록에서 사라졌으면(다른 기기에서 삭제) 편집판도 비운다.
      final keep = draft;
      if (keep != null && keep.id.isNotEmpty) {
        _pick(items!.where((n) => n.id == keep.id).firstOrNull);
      }
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// 편집판을 [n] 으로 바꾼다. null 이면 아무것도 안 고르는 상태.
  void _pick(Notice? n) {
    setState(() {
      draft = n?.copy();
      title.text = n?.title ?? '';
      body.text = n?.body ?? '';
      sends = [];
    });
    if (n != null && n.id.isNotEmpty) _loadSends(n.id);
  }

  Future<void> _loadSends(String noticeId) async {
    try {
      final s = await remote.noticeSends(noticeId);
      if (mounted && draft?.id == noticeId) setState(() => sends = s);
    } catch (e) {
      debugPrint('보낸 기록을 못 읽었습니다: $e'); // 기록은 없어도 공지 작업은 된다
    }
  }

  void _newNotice() {
    final g = current.value;
    if (g == null) return;
    _pick(Notice(gatheringId: g.id));
  }

  Future<void> _save() async {
    final d = draft;
    if (d == null) return;
    d.title = title.text.trim();
    d.body = body.text.trim();
    if (d.title.isEmpty) {
      setState(() => error = '공지 제목을 입력하세요.');
      return;
    }
    if (!await ensureAdmin(context)) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await remote.saveNotice(d);
      items = sortedNotices([
        for (final n in items ?? <Notice>[])
          if (n.id != saved.id) n,
        saved,
      ]);
      _pick(saved);
      _snack('저장했습니다.${saved.published ? ' 신청 웹에 바로 반영됩니다.' : ' 비공개라 신청 웹에는 안 보입니다.'}');
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _delete() async {
    final d = draft;
    if (d == null || d.id.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: '공지 삭제',
      body: '"${d.title}" 공지와 그 보낸 기록을 지웁니다. 되돌릴 수 없습니다.',
      action: '삭제',
      danger: true,
    );
    if (!ok) return;
    setState(() => saving = true);
    try {
      await remote.deleteNotice(d.id);
      items = [
        for (final n in items ?? <Notice>[])
          if (n.id != d.id) n,
      ];
      _pick(null);
      _snack('공지를 지웠습니다.');
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// 클립보드에 넣고 기록을 남긴다. 기록이 실패해도 복사는 이미 된 것이므로 막지 않는다.
  Future<void> _copy(String text, NoticeChannel channel, int count) async {
    final d = draft;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack(
      channel == NoticeChannel.phones
          ? '휴대폰 번호 $count개를 복사했습니다.'
          : '메시지를 복사했습니다. 카카오톡 단톡방에 붙여넣으세요.',
    );
    if (d == null || d.id.isEmpty) return;
    try {
      final s = await remote.logNoticeSend(d.id, channel, target, count);
      if (mounted && draft?.id == d.id) setState(() => sends = [s, ...sends]);
    } catch (e) {
      debugPrint('보낸 기록을 남기지 못했습니다: $e');
    }
  }

  Future<void> _sendAlimtalk(Gathering g, List<String> phones) async {
    final d = draft;
    if (d == null || d.id.isEmpty || phones.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: '알림톡으로 보내기',
      body:
          '${target.labelFor(free: g.fee.isFree)} ${phones.length}명에게 알림톡을 보냅니다. '
          '보낸 알림톡은 취소할 수 없고 건당 요금이 붙습니다.',
      action: '보내기',
    );
    if (!ok) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final sent = await remote.sendNoticeKakao(
        notice: d,
        target: target,
        phones: phones,
        message: noticeMessage(g, d),
      );
      _snack('알림톡 $sent건을 보냈습니다.');
      await _loadSends(d.id);
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = current.value;
    if (g == null) {
      return const EmptyNotice(
        icon: Icons.cloud_off_outlined,
        text: '서버에 연결된 집회에서만 공지를 쓸 수 있습니다.',
      );
    }
    if (!remote.signedIn) {
      return EmptyNotice(
        icon: Icons.lock_outline,
        text: '공지 관리는 운영자 로그인이 필요합니다.',
        action: FilledButton(
          onPressed: () async {
            if (await ensureAdmin(context)) _load();
          },
          child: const Text('운영자 로그인'),
        ),
      );
    }
    if (items == null) {
      return loading
          ? const Center(child: CircularProgressIndicator())
          : EmptyNotice(
              icon: Icons.cloud_off_outlined,
              text: error ?? '공지를 불러오지 못했습니다.',
              action: OutlinedButton(
                onPressed: _load,
                child: const Text('다시 시도'),
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              SectionTitle(
                '공지 ${items!.length}건',
                subtitle: '공개한 공지는 신청 웹에 뜹니다. 카카오톡은 메시지를 복사해 단톡방에 붙여넣습니다.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('새로고침'),
                  ),
                  FilledButton.icon(
                    onPressed: _newNotice,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('새 공지'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _list()),
              const VerticalDivider(width: 1),
              Expanded(child: _editor(g)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list() {
    if (items!.isEmpty) {
      return EmptyNotice(
        icon: Icons.campaign_outlined,
        text: '아직 공지가 없습니다.',
        action: FilledButton(
          onPressed: _newNotice,
          child: const Text('첫 공지 쓰기'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items!.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _NoticeCard(
        notice: items![i],
        selected: draft?.id.isNotEmpty == true && items![i].id == draft!.id,
        onTap: () => _pick(items![i]),
      ),
    );
  }

  Widget _editor(Gathering g) {
    final d = draft;
    if (d == null) {
      return const EmptyNotice(
        icon: Icons.touch_app_outlined,
        text: '왼쪽에서 공지를 고르거나 [새 공지]를 누르세요.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        _card('공지 내용', [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: '제목 *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 6,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: '내용',
              hintText: '카카오톡에 그대로 붙여넣을 글입니다. 꾸밈 없이 쓰세요.',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _toggle(
                '신청 웹에 공개',
                d.published,
                (v) => setState(() => d.published = v),
              ),
              _toggle('맨 위 고정', d.pinned, (v) => setState(() => d.pinned = v)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(saving ? '저장 중…' : '저장'),
              ),
              OutlinedButton.icon(
                onPressed: saving || d.id.isEmpty ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('삭제'),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),
        _sendCard(g, d),
      ],
    );
  }

  Widget _sendCard(Gathering g, Notice d) {
    final free = g.fee.isFree;
    final phones = noticePhones(regs, target);
    final people = noticeTargets(
      regs,
      target,
    ).fold(0, (s, r) => s + r.people.length);
    // 저장 전에는 보낸 기록을 붙일 공지가 없다. 미리보기는 그대로 보여준다.
    final saved = d.id.isNotEmpty;
    final message = noticeMessage(
      g,
      d.copy()
        ..title = title.text.trim()
        ..body = body.text.trim(),
    );

    return _card('카카오톡으로 보내기', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in NoticeTarget.values)
            ChoiceChip(
              label: Text(
                '${t.labelFor(free: free)} ${noticeTargets(regs, t).length}',
              ),
              selected: target == t,
              onSelected: (_) => setState(() => target = t),
            ),
          Text(
            '받는 사람 ${phones.length}명 · 참석 $people명',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.border),
        ),
        child: SelectableText(
          message,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: title.text.trim().isEmpty
                ? null
                : () => _copy(message, NoticeChannel.copy, phones.length),
            icon: const Icon(Icons.content_copy, size: 18),
            label: const Text('메시지 복사'),
          ),
          OutlinedButton.icon(
            // 사람이 보고 쓰는 목록이라 여기서만 010-1234-5678 꼴로 바꾼다.
            onPressed: phones.isEmpty
                ? null
                : () => _copy(
                    phones.map(fmtPhone).join('\n'),
                    NoticeChannel.phones,
                    phones.length,
                  ),
            icon: const Icon(Icons.phone_outlined, size: 18),
            label: const Text('번호 복사'),
          ),
          OutlinedButton.icon(
            onPressed: saving || !saved || phones.isEmpty
                ? null
                : () => _sendAlimtalk(g, phones),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('알림톡으로 보내기'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        '카카오톡은 전화번호만으로 보낼 수 없습니다. [메시지 복사] 후 단톡방에 붙여넣는 게 기본이고, '
        '[알림톡]은 채널·대행사·템플릿 승인을 마친 뒤에만 됩니다.',
        style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textMuted),
      ),
      if (!saved)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '저장하지 않은 공지는 보낸 기록이 남지 않습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.warnInk),
          ),
        ),
      if (sends.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text(
          '돌린 기록',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        for (final s in sends)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${fmtDate(s.sentAt)} ${_hm(s.sentAt)} · ${s.summary(free: free)}',
              style: const TextStyle(fontSize: 13, fontFeatures: tabular),
            ),
          ),
      ],
    ]);
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ],
  );

  Widget _card(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 왼쪽 목록의 공지 한 칸.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.selected,
    required this.onTap,
  });
  final Notice notice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.brandSoft : AppColors.surface,
    // shape 와 borderRadius 를 같이 주면 런타임 assert 로 죽는다 (room-ui §5).
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.tile),
      side: BorderSide(
        color: selected ? AppColors.brand : AppColors.border,
        width: selected ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.tile),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (notice.pinned) ...[
                  const Icon(
                    Icons.push_pin_outlined,
                    size: 14,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    notice.title.isEmpty ? '(제목 없음)' : notice.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: notice.published
                          ? AppColors.text
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                if (!notice.published)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.fill,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '비공개',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${fmtDate(notice.createdAt)}${notice.body.isEmpty ? '' : ' · ${notice.body.replaceAll('\n', ' ')}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textFaint,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
