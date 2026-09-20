/// 담당구역 할 일 표. 스탭 페이지(휴대폰)와 운영자 화면이 같은 위젯을 쓴다 (dart:io 금지).
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// [구분 | 내용 | 수량 | 체크] 표. 행을 고치거나 더하거나 지우면 [onChanged] 를 부른다.
/// 목록 자체를 제자리에서 고치므로 부모는 그냥 저장만 하면 된다.
class DutyTaskTable extends StatefulWidget {
  const DutyTaskTable({
    super.key,
    required this.items,
    required this.onChanged,
    required this.newId,
    this.readOnly = false,
  });

  final List<DutyTask> items;

  /// 한 칸이라도 바뀌면 불린다. 저장은 부모가 한다.
  final VoidCallback onChanged;

  /// 새 행의 id 를 만드는 함수 (운영자는 store.newId, 스탭 페이지는 시간 기반).
  final String Function() newId;
  final bool readOnly;

  @override
  State<DutyTaskTable> createState() => _DutyTaskTableState();
}

class _DutyTaskTableState extends State<DutyTaskTable> {
  /// 행 id → 입력칸. 행을 지워도 남은 칸이 엉키지 않게 id 로 들고 있는다.
  final _ctl = <String, (TextEditingController, TextEditingController, TextEditingController)>{};

  (TextEditingController, TextEditingController, TextEditingController) _of(
    DutyTask t,
  ) => _ctl.putIfAbsent(
    t.id,
    () => (
      TextEditingController(text: t.kind),
      TextEditingController(text: t.content),
      TextEditingController(text: t.qty),
    ),
  );

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.$1.dispose();
      c.$2.dispose();
      c.$3.dispose();
    }
    super.dispose();
  }

  void _add() {
    setState(() => widget.items.add(DutyTask(id: widget.newId())));
    widget.onChanged();
  }

  void _remove(DutyTask t) {
    setState(() => widget.items.removeWhere((x) => x.id == t.id));
    _ctl.remove(t.id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _HeaderRow(),
      for (final t in widget.items) _row(t),
      if (widget.items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text(
            '적어 둔 할 일이 없습니다.',
            style: TextStyle(fontSize: 13, color: AppColors.textFaint),
          ),
        ),
      if (!widget.readOnly)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('행 추가'),
          ),
        ),
    ],
  );

  Widget _row(DutyTask t) {
    final (kind, content, qty) = _of(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 84,
            child: _cell(
              kind,
              '구분',
              (v) => t.kind = v,
              enabled: !widget.readOnly,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              content,
              '내용',
              (v) => t.content = v,
              enabled: !widget.readOnly,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: _cell(
              qty,
              '수량',
              (v) => t.qty = v,
              enabled: !widget.readOnly,
            ),
          ),
          SizedBox(
            width: 40,
            child: Checkbox(
              value: t.done,
              onChanged: widget.readOnly
                  ? null
                  : (v) {
                      setState(() => t.done = v ?? false);
                      widget.onChanged();
                    },
            ),
          ),
          SizedBox(
            width: 32,
            child: widget.readOnly
                ? null
                : IconButton(
                    tooltip: '이 줄 지우기',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: () => _remove(t),
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.textFaint,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    TextEditingController c,
    String hint,
    void Function(String) set, {
    required bool enabled,
  }) => TextField(
    controller: c,
    enabled: enabled,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: const OutlineInputBorder(),
    ),
    onChanged: (v) {
      set(v);
      widget.onChanged();
    },
  );
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 6, left: 2),
    child: Row(
      children: [
        SizedBox(width: 84, child: _Head('구분')),
        SizedBox(width: 6),
        Expanded(child: _Head('내용')),
        SizedBox(width: 6),
        SizedBox(width: 64, child: _Head('수량')),
        SizedBox(width: 40, child: _Head('체크')),
        SizedBox(width: 32),
      ],
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );
}
